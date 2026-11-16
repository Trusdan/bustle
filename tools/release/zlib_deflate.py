# Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan)
"""Raw deflate, written in pure Python, that gives the same bytes as classic zlib.

`compress(data)` returns exactly what classic zlib (madler/zlib 1.2.12 to 1.3.1) writes for
`zlib.compressobj(9, zlib.DEFLATED, -15)`, then `compress(data)` and `flush()`: compression
level 9, a raw stream (no header or trailer), a 32 KiB window, memLevel 8 and the default
strategy. That is what Python's zipfile asks of zlib for a deflated entry at compresslevel 9.

Why: other zlib builds (zlib-ng, which some systems ship as their zlib) compress the same input
to different, equally valid bytes, so a zip built on one machine would not match one built on
another. tools/build_release.sh uses this module instead of the system's zlib, so the release
zips are byte-identical everywhere. Decompressing works with any zlib.

It follows zlib's deflate.c (deflate_slow, longest_match, fill_window) and trees.c step by step.
Only level 9 and the default strategy are implemented. tools/test_release_deflate.py checks it
against the system zlib when that is classic zlib, and that any zlib decompresses it.
"""

MIN_MATCH = 3
MAX_MATCH = 258
W_BITS = 15
W_SIZE = 1 << W_BITS
W_MASK = W_SIZE - 1
WINDOW_SIZE = 2 * W_SIZE
HASH_BITS = 8 + 7  # memLevel 8
HASH_SIZE = 1 << HASH_BITS
HASH_MASK = HASH_SIZE - 1
HASH_SHIFT = (HASH_BITS + MIN_MATCH - 1) // MIN_MATCH
MIN_LOOKAHEAD = MAX_MATCH + MIN_MATCH + 1
MAX_DIST = W_SIZE - MIN_LOOKAHEAD
WIN_INIT = MAX_MATCH
TOO_FAR = 4096
LIT_BUFSIZE = 1 << (8 + 6)
SYM_LIMIT = LIT_BUFSIZE - 1  # symbols per block before a flush (sym_end / 3)

# Level 9: good_length, max_lazy, nice_length, max_chain.
GOOD_MATCH, MAX_LAZY, NICE_MATCH, MAX_CHAIN = 32, 258, 258, 4096

LITERALS = 256
LENGTH_CODES = 29
L_CODES = LITERALS + 1 + LENGTH_CODES
D_CODES = 30
BL_CODES = 19
HEAP_SIZE = 2 * L_CODES + 1
MAX_BITS = 15
MAX_BL_BITS = 7
END_BLOCK = 256
REP_3_6, REPZ_3_10, REPZ_11_138 = 16, 17, 18

EXTRA_LBITS = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
EXTRA_DBITS = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
EXTRA_BLBITS = [0] * 16 + [2, 3, 7]
BL_ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]


def _bi_reverse(code, length):
    res = 0
    while True:
        res |= code & 1
        code >>= 1
        res <<= 1
        length -= 1
        if length <= 0:
            return res >> 1


def _tables():
    """zlib's tr_static_init: the length and distance code tables and the static trees."""
    base_length = [0] * LENGTH_CODES
    length_code = [0] * 256
    length = 0
    for code in range(LENGTH_CODES - 1):
        base_length[code] = length
        for _ in range(1 << EXTRA_LBITS[code]):
            length_code[length] = code
            length += 1
    length_code[length - 1] = LENGTH_CODES - 1
    base_dist = [0] * D_CODES
    dist_code = [0] * 512
    dist = 0
    for code in range(16):
        base_dist[code] = dist
        for _ in range(1 << EXTRA_DBITS[code]):
            dist_code[dist] = code
            dist += 1
    dist >>= 7
    for code in range(16, D_CODES):
        base_dist[code] = dist << 7
        for _ in range(1 << (EXTRA_DBITS[code] - 7)):
            dist_code[256 + dist] = code
            dist += 1
    static_llen = [8] * 144 + [9] * 112 + [7] * 24 + [8] * 8
    bl_count = [0] * (MAX_BITS + 1)
    for n in static_llen:
        bl_count[n] += 1
    static_lcode = _gen_codes(static_llen, L_CODES + 1, bl_count)
    static_dlen = [5] * D_CODES
    static_dcode = [_bi_reverse(n, 5) for n in range(D_CODES)]
    return base_length, length_code, base_dist, dist_code, static_llen, static_lcode, static_dlen, static_dcode


def _gen_codes(lengths, max_code, bl_count):
    next_code = [0] * (MAX_BITS + 1)
    code = 0
    for bits in range(1, MAX_BITS + 1):
        code = (code + bl_count[bits - 1]) << 1
        next_code[bits] = code
    codes = [0] * len(lengths)
    for n in range(max_code + 1):
        length = lengths[n]
        if length == 0:
            continue
        codes[n] = _bi_reverse(next_code[length], length)
        next_code[length] += 1
    return codes


(BASE_LENGTH, LENGTH_CODE, BASE_DIST, DIST_CODE,
 STATIC_LLEN, STATIC_LCODE, STATIC_DLEN, STATIC_DCODE) = _tables()


def _d_code(dist):
    return DIST_CODE[dist] if dist < 256 else DIST_CODE[256 + (dist >> 7)]


class _Tree:
    """One dynamic tree (zlib's ct_data array and tree_desc), with freq, code, dad and len kept
    apart. zlib shares freq with code and dad with len; nothing here reads one after the other is
    written, so keeping them apart changes nothing."""

    def __init__(self, elems, static_len, extra, extra_base, max_length):
        self.elems = elems
        self.static_len = static_len
        self.extra = extra
        self.extra_base = extra_base
        self.max_length = max_length
        self.freq = [0] * HEAP_SIZE
        self.code = [0] * HEAP_SIZE
        self.dad = [0] * HEAP_SIZE
        self.len = [0] * HEAP_SIZE
        self.max_code = 0


class _Deflate:
    def __init__(self, data):
        self.data = data
        self.next_in = 0
        self.window = bytearray(WINDOW_SIZE)
        self.prev = [0] * W_SIZE
        self.head = [0] * HASH_SIZE
        self.ins_h = 0
        self.strstart = 0
        self.block_start = 0
        self.lookahead = 0
        self.insert = 0
        self.match_length = MIN_MATCH - 1
        self.prev_length = MIN_MATCH - 1
        self.match_start = 0
        self.prev_match = 0
        self.match_available = False
        self.high_water = 0
        self.out = bytearray()
        self.bit_buf = 0
        self.bit_count = 0
        self.ltree = _Tree(L_CODES, STATIC_LLEN, EXTRA_LBITS, LITERALS + 1, MAX_BITS)
        self.dtree = _Tree(D_CODES, STATIC_DLEN, EXTRA_DBITS, 0, MAX_BITS)
        self.bltree = _Tree(BL_CODES, None, EXTRA_BLBITS, 0, MAX_BL_BITS)
        self.syms = []
        self.opt_len = 0
        self.static_len = 0
        self.heap = [0] * HEAP_SIZE
        self.heap_len = 0
        self.heap_max = 0
        self.depth = [0] * HEAP_SIZE
        self.bl_count = [0] * (MAX_BITS + 1)
        self._init_block()

    # ---- bit output (zlib's send_bits, bi_windup) ----

    def _send_bits(self, value, length):
        self.bit_buf |= value << self.bit_count
        self.bit_count += length
        while self.bit_count >= 8:
            self.out.append(self.bit_buf & 0xFF)
            self.bit_buf >>= 8
            self.bit_count -= 8

    def _windup(self):
        if self.bit_count > 0:
            self.out.append(self.bit_buf & 0xFF)
        self.bit_buf = 0
        self.bit_count = 0

    # ---- the window (fill_window) ----

    def _fill_window(self):
        window = self.window
        while True:
            more = WINDOW_SIZE - self.lookahead - self.strstart
            if self.strstart >= W_SIZE + MAX_DIST:
                window[0:W_SIZE - more] = window[W_SIZE:W_SIZE + W_SIZE - more]
                self.match_start -= W_SIZE
                self.strstart -= W_SIZE
                self.block_start -= W_SIZE
                if self.insert > self.strstart:
                    self.insert = self.strstart
                self.head = [m - W_SIZE if m >= W_SIZE else 0 for m in self.head]
                self.prev = [m - W_SIZE if m >= W_SIZE else 0 for m in self.prev]
                more += W_SIZE
            if self.next_in >= len(self.data):
                break
            chunk = self.data[self.next_in:self.next_in + more]
            start = self.strstart + self.lookahead
            window[start:start + len(chunk)] = chunk
            self.next_in += len(chunk)
            self.lookahead += len(chunk)
            if self.lookahead + self.insert >= MIN_MATCH:
                pos = self.strstart - self.insert
                h = window[pos]
                h = ((h << HASH_SHIFT) ^ window[pos + 1]) & HASH_MASK
                while self.insert:
                    h = ((h << HASH_SHIFT) ^ window[pos + MIN_MATCH - 1]) & HASH_MASK
                    self.prev[pos & W_MASK] = self.head[h]
                    self.head[h] = pos
                    pos += 1
                    self.insert -= 1
                    if self.lookahead + self.insert < MIN_MATCH:
                        break
                self.ins_h = h
            if not (self.lookahead < MIN_LOOKAHEAD and self.next_in < len(self.data)):
                break
        if self.high_water < WINDOW_SIZE:
            curr = self.strstart + self.lookahead
            if self.high_water < curr:
                init = min(WINDOW_SIZE - curr, WIN_INIT)
                window[curr:curr + init] = bytes(init)
                self.high_water = curr + init
            elif self.high_water < curr + WIN_INIT:
                init = min(curr + WIN_INIT - self.high_water, WINDOW_SIZE - self.high_water)
                window[self.high_water:self.high_water + init] = bytes(init)
                self.high_water += init

    def _insert_string(self, pos):
        h = ((self.ins_h << HASH_SHIFT) ^ self.window[pos + MIN_MATCH - 1]) & HASH_MASK
        self.ins_h = h
        head = self.head[h]
        self.prev[pos & W_MASK] = head
        self.head[h] = pos
        return head

    # ---- longest_match ----

    def _longest_match(self, cur_match):
        window = self.window
        prev = self.prev
        chain_length = MAX_CHAIN
        scan = self.strstart
        best_len = self.prev_length
        nice_match = NICE_MATCH
        limit = self.strstart - MAX_DIST if self.strstart > MAX_DIST else 0
        if self.prev_length >= GOOD_MATCH:
            chain_length >>= 2
        if nice_match > self.lookahead:
            nice_match = self.lookahead
        scan0 = window[scan]
        scan1 = window[scan + 1]
        scan_end1 = window[scan + best_len - 1]
        scan_end = window[scan + best_len]
        strend = scan + MAX_MATCH
        match_start = self.match_start
        while True:
            m = cur_match
            if (window[m + best_len] == scan_end and window[m + best_len - 1] == scan_end1
                    and window[m] == scan0 and window[m + 1] == scan1):
                # Bytes 0 to 2 match (2 by the hash). Find where the strings first differ, up to
                # MAX_MATCH, by halving: slice comparison runs in C.
                lo, hi = 3, MAX_MATCH
                if window[m + 3:m + MAX_MATCH] == window[scan + 3:strend]:
                    length = MAX_MATCH
                else:
                    while lo < hi:
                        mid = (lo + hi + 1) >> 1
                        if window[m + lo:m + mid] == window[scan + lo:scan + mid]:
                            lo = mid
                        else:
                            hi = mid - 1
                    length = lo
                if length > best_len:
                    match_start = cur_match
                    best_len = length
                    if length >= nice_match:
                        break
                    scan_end1 = window[scan + best_len - 1]
                    scan_end = window[scan + best_len]
            cur_match = prev[cur_match & W_MASK]
            if cur_match <= limit:
                break
            chain_length -= 1
            if chain_length == 0:
                break
        self.match_start = match_start
        return best_len if best_len <= self.lookahead else self.lookahead

    # ---- deflate_slow ----

    def run(self):
        while True:
            if self.lookahead < MIN_LOOKAHEAD:
                self._fill_window()
                if self.lookahead == 0:
                    break
            hash_head = 0
            if self.lookahead >= MIN_MATCH:
                hash_head = self._insert_string(self.strstart)
            self.prev_length = self.match_length
            self.prev_match = self.match_start
            self.match_length = MIN_MATCH - 1
            if hash_head != 0 and self.prev_length < MAX_LAZY and self.strstart - hash_head <= MAX_DIST:
                self.match_length = self._longest_match(hash_head)
                if self.match_length == MIN_MATCH and self.strstart - self.match_start > TOO_FAR:
                    self.match_length = MIN_MATCH - 1
            if self.prev_length >= MIN_MATCH and self.match_length <= self.prev_length:
                max_insert = self.strstart + self.lookahead - MIN_MATCH
                flush = self._tally(self.strstart - 1 - self.prev_match, self.prev_length - MIN_MATCH)
                self.lookahead -= self.prev_length - 1
                count = self.prev_length - 2
                while count:
                    self.strstart += 1
                    if self.strstart <= max_insert:
                        self._insert_string(self.strstart)
                    count -= 1
                self.prev_length = 0
                self.match_available = False
                self.match_length = MIN_MATCH - 1
                self.strstart += 1
                if flush:
                    self._flush_block(False)
            elif self.match_available:
                if self._tally(0, self.window[self.strstart - 1]):
                    self._flush_block(False)
                self.strstart += 1
                self.lookahead -= 1
            else:
                self.match_available = True
                self.strstart += 1
                self.lookahead -= 1
        if self.match_available:
            self._tally(0, self.window[self.strstart - 1])
            self.match_available = False
        self.insert = min(self.strstart, MIN_MATCH - 1)
        self._flush_block(True)
        return bytes(self.out)

    # ---- trees.c ----

    def _init_block(self):
        for tree in (self.ltree, self.dtree, self.bltree):
            for n in range(tree.elems):
                tree.freq[n] = 0
        self.ltree.freq[END_BLOCK] = 1
        self.opt_len = 0
        self.static_len = 0
        self.syms = []

    def _tally(self, dist, lc):
        self.syms.append((dist, lc))
        if dist == 0:
            self.ltree.freq[lc] += 1
        else:
            dist -= 1
            self.ltree.freq[LENGTH_CODE[lc] + LITERALS + 1] += 1
            self.dtree.freq[_d_code(dist)] += 1
        return len(self.syms) == SYM_LIMIT

    def _flush_block(self, last):
        stored_len = self.strstart - self.block_start
        buf_start = self.block_start
        self._build_tree(self.ltree)
        self._build_tree(self.dtree)
        max_blindex = self._build_bl_tree()
        opt_lenb = (self.opt_len + 3 + 7) >> 3
        static_lenb = (self.static_len + 3 + 7) >> 3
        if static_lenb <= opt_lenb:
            opt_lenb = static_lenb
        if stored_len + 4 <= opt_lenb and buf_start >= 0:
            self._send_bits(last, 3)
            self._windup()
            self.out += bytes((stored_len & 0xFF, (stored_len >> 8) & 0xFF,
                               ~stored_len & 0xFF, (~stored_len >> 8) & 0xFF))
            self.out += self.window[buf_start:buf_start + stored_len]
        elif static_lenb == opt_lenb:
            self._send_bits((1 << 1) + last, 3)
            self._compress_block(STATIC_LCODE, STATIC_LLEN, STATIC_DCODE, STATIC_DLEN)
        else:
            self._send_bits((2 << 1) + last, 3)
            self._send_all_trees(self.ltree.max_code + 1, self.dtree.max_code + 1, max_blindex + 1)
            self._compress_block(self.ltree.code, self.ltree.len, self.dtree.code, self.dtree.len)
        self._init_block()
        if last:
            self._windup()
        self.block_start = self.strstart

    def _smaller(self, tree, n, m):
        fn, fm = tree.freq[n], tree.freq[m]
        return fn < fm or (fn == fm and self.depth[n] <= self.depth[m])

    def _pqdownheap(self, tree, k):
        heap = self.heap
        v = heap[k]
        j = k << 1
        while j <= self.heap_len:
            if j < self.heap_len and self._smaller(tree, heap[j + 1], heap[j]):
                j += 1
            if self._smaller(tree, v, heap[j]):
                break
            heap[k] = heap[j]
            k = j
            j <<= 1
        heap[k] = v

    def _build_tree(self, tree):
        heap = self.heap
        depth = self.depth
        elems = tree.elems
        max_code = -1
        self.heap_len = 0
        self.heap_max = HEAP_SIZE
        for n in range(elems):
            if tree.freq[n] != 0:
                self.heap_len += 1
                heap[self.heap_len] = max_code = n
                depth[n] = 0
            else:
                tree.len[n] = 0
        while self.heap_len < 2:
            if max_code < 2:
                max_code += 1
                node = max_code
            else:
                node = 0
            self.heap_len += 1
            heap[self.heap_len] = node
            tree.freq[node] = 1
            depth[node] = 0
            self.opt_len -= 1
            if tree.static_len is not None:
                self.static_len -= tree.static_len[node]
        tree.max_code = max_code
        for n in range(self.heap_len // 2, 0, -1):
            self._pqdownheap(tree, n)
        node = elems
        while True:
            n = heap[1]
            heap[1] = heap[self.heap_len]
            self.heap_len -= 1
            self._pqdownheap(tree, 1)
            m = heap[1]
            self.heap_max -= 1
            heap[self.heap_max] = n
            self.heap_max -= 1
            heap[self.heap_max] = m
            tree.freq[node] = tree.freq[n] + tree.freq[m]
            depth[node] = (depth[n] if depth[n] >= depth[m] else depth[m]) + 1
            tree.dad[n] = tree.dad[m] = node
            heap[1] = node
            node += 1
            self._pqdownheap(tree, 1)
            if self.heap_len < 2:
                break
        self.heap_max -= 1
        heap[self.heap_max] = heap[1]
        self._gen_bitlen(tree)
        codes = _gen_codes(tree.len, max_code, self.bl_count)
        for n in range(max_code + 1):
            tree.code[n] = codes[n]

    def _gen_bitlen(self, tree):
        heap = self.heap
        bl_count = self.bl_count
        max_code = tree.max_code
        max_length = tree.max_length
        for bits in range(MAX_BITS + 1):
            bl_count[bits] = 0
        tree.len[heap[self.heap_max]] = 0
        overflow = 0
        h = self.heap_max + 1
        while h < HEAP_SIZE:
            n = heap[h]
            bits = tree.len[tree.dad[n]] + 1
            if bits > max_length:
                bits = max_length
                overflow += 1
            tree.len[n] = bits
            h += 1
            if n > max_code:
                continue
            bl_count[bits] += 1
            xbits = tree.extra[n - tree.extra_base] if n >= tree.extra_base else 0
            f = tree.freq[n]
            self.opt_len += f * (bits + xbits)
            if tree.static_len is not None:
                self.static_len += f * (tree.static_len[n] + xbits)
        if overflow == 0:
            return
        while overflow > 0:
            bits = max_length - 1
            while bl_count[bits] == 0:
                bits -= 1
            bl_count[bits] -= 1
            bl_count[bits + 1] += 2
            bl_count[max_length] -= 1
            overflow -= 2
        h = HEAP_SIZE
        for bits in range(max_length, 0, -1):
            n = bl_count[bits]
            while n != 0:
                h -= 1
                m = heap[h]
                if m > max_code:
                    continue
                if tree.len[m] != bits:
                    self.opt_len += (bits - tree.len[m]) * tree.freq[m]
                    tree.len[m] = bits
                n -= 1

    def _scan_tree(self, tree, max_code):
        bl_freq = self.bltree.freq
        lens = tree.len
        prevlen = -1
        nextlen = lens[0]
        count = 0
        max_count, min_count = (138, 3) if nextlen == 0 else (7, 4)
        lens[max_code + 1] = 0xFFFF
        for n in range(max_code + 1):
            curlen = nextlen
            nextlen = lens[n + 1]
            count += 1
            if count < max_count and curlen == nextlen:
                continue
            elif count < min_count:
                bl_freq[curlen] += count
            elif curlen != 0:
                if curlen != prevlen:
                    bl_freq[curlen] += 1
                bl_freq[REP_3_6] += 1
            elif count <= 10:
                bl_freq[REPZ_3_10] += 1
            else:
                bl_freq[REPZ_11_138] += 1
            count = 0
            prevlen = curlen
            if nextlen == 0:
                max_count, min_count = 138, 3
            elif curlen == nextlen:
                max_count, min_count = 6, 3
            else:
                max_count, min_count = 7, 4

    def _send_tree(self, tree, max_code):
        bl_code, bl_len = self.bltree.code, self.bltree.len
        lens = tree.len
        prevlen = -1
        nextlen = lens[0]
        count = 0
        max_count, min_count = (138, 3) if nextlen == 0 else (7, 4)
        for n in range(max_code + 1):
            curlen = nextlen
            nextlen = lens[n + 1]
            count += 1
            if count < max_count and curlen == nextlen:
                continue
            elif count < min_count:
                while count:
                    self._send_bits(bl_code[curlen], bl_len[curlen])
                    count -= 1
            elif curlen != 0:
                if curlen != prevlen:
                    self._send_bits(bl_code[curlen], bl_len[curlen])
                    count -= 1
                self._send_bits(bl_code[REP_3_6], bl_len[REP_3_6])
                self._send_bits(count - 3, 2)
            elif count <= 10:
                self._send_bits(bl_code[REPZ_3_10], bl_len[REPZ_3_10])
                self._send_bits(count - 3, 3)
            else:
                self._send_bits(bl_code[REPZ_11_138], bl_len[REPZ_11_138])
                self._send_bits(count - 11, 7)
            count = 0
            prevlen = curlen
            if nextlen == 0:
                max_count, min_count = 138, 3
            elif curlen == nextlen:
                max_count, min_count = 6, 3
            else:
                max_count, min_count = 7, 4

    def _build_bl_tree(self):
        self._scan_tree(self.ltree, self.ltree.max_code)
        self._scan_tree(self.dtree, self.dtree.max_code)
        self._build_tree(self.bltree)
        max_blindex = BL_CODES - 1
        while max_blindex >= 3:
            if self.bltree.len[BL_ORDER[max_blindex]] != 0:
                break
            max_blindex -= 1
        self.opt_len += 3 * (max_blindex + 1) + 5 + 5 + 4
        return max_blindex

    def _send_all_trees(self, lcodes, dcodes, blcodes):
        self._send_bits(lcodes - 257, 5)
        self._send_bits(dcodes - 1, 5)
        self._send_bits(blcodes - 4, 4)
        for rank in range(blcodes):
            self._send_bits(self.bltree.len[BL_ORDER[rank]], 3)
        self._send_tree(self.ltree, lcodes - 1)
        self._send_tree(self.dtree, dcodes - 1)

    def _compress_block(self, lcode, llen, dcode, dlen):
        send = self._send_bits
        for dist, lc in self.syms:
            if dist == 0:
                send(lcode[lc], llen[lc])
            else:
                code = LENGTH_CODE[lc]
                send(lcode[code + LITERALS + 1], llen[code + LITERALS + 1])
                extra = EXTRA_LBITS[code]
                if extra:
                    send(lc - BASE_LENGTH[code], extra)
                dist -= 1
                code = _d_code(dist)
                send(dcode[code], dlen[code])
                extra = EXTRA_DBITS[code]
                if extra:
                    send(dist - BASE_DIST[code], extra)
        send(lcode[END_BLOCK], llen[END_BLOCK])


def compress(data):
    """Raw deflate of [data], byte-for-byte what classic zlib writes at level 9 (see above)."""
    return _Deflate(bytes(data)).run()


class Compressor:
    """A stand-in for zlib.compressobj(9, zlib.DEFLATED, -15), for zipfile: it collects the input
    and compresses it all at flush()."""

    def __init__(self):
        self._parts = []

    def compress(self, data):
        self._parts.append(bytes(data))
        return b""

    def flush(self, *_mode):
        return compress(b"".join(self._parts))
