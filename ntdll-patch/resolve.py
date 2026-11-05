#!/usr/bin/env python3
import hashlib, pathlib, struct, sys, re, bisect, capstone
from capstone import x86 as X86, arm64 as A64

ARCH = {0x8664: 'x86_64-windows', 0x14c: 'i386-windows', 0xaa64: 'aarch64-windows'}

PAYLOAD = {0x8664: 864, 0x14c: 1376, 0xaa64: 868}
SECTION_CHARACTERISTICS_OFFSET = 36
IMAGE_SCN_MEM_DISCARDABLE = 0x02000000
IMAGE_SCN_MEM_EXECUTE = 0x20000000
IMAGE_SCN_MEM_WRITE = 0x80000000

PINNED = {
    '04c7200b6645decb7c2d1ba6b0195abc9af83257072558d11aa72cc067ac3377':
        {'hookRVA': 0x51f15, 'stolen': '4883bc24f000000000', 'caveRVA': 0x80be0, 'wm': 'rsi',
         'resume': 0x51f1e, 'load_path': 0xd0,
         'payload': '4ce2ddc11c433fe15f78633fc5c1fda8b27fa642426cb26378f7d7d7b54a79f8',
         'exports': {'LdrGetDllHandle': 0x1700176d0, 'LdrLoadDll': 0x1700181f0,
                     'NtProtectVirtualMemory': 0x17000f640}},
    '4dbe6a8b3e7ee1c1e7f593befd14e01913199da833dd699da966be2026daae2a':
        {'hookRVA': 0x485f3, 'stolen': '4883bc24f000000000', 'caveRVA': 0x7a3e0, 'wm': 'r15',
         'resume': 0x485fc, 'load_path': 0xd0,
         'payload': '3c641518f1fef6a711bce103e63cbfb4c342c25f3d0651c35d98202dd9fa01f2',
         'exports': {'LdrGetDllHandle': 0x170014fe0, 'LdrLoadDll': 0x170015b50,
                     'NtProtectVirtualMemory': 0x17000f380}},
    '94cc7c14c1e9dcf58ef501015c115f8405c73b2a65cefe31faa5d9e47f36e58b':
        {'hookRVA': 0x4d828, 'stolen': 'f645bc027526', 'caveRVA': 0x7c830, 'caveSize': 2000,
         'resume': 0x4d82e, 'wm': 'edi', 'load_path': -0x54,
         'payload': '2758d4f6783c853c460187f83f4fb9b1105380d194126ef83fc85e2596d3036a',
         'exports': {'LdrGetDllHandle': 0x7bc125b0, 'LdrLoadDll': 0x7bc130a0,
                     'NtProtectVirtualMemory': 0x7bc0d764, 'NtOpenFile': 0x7bc0d594,
                     'NtReadFile': 0x7bc0d2c4, 'NtClose': 0x7bc0d354}},
    '09474795d6f306163cebab6429819999fcff50e07dbc4b067a90ec4f74a3a7d7':
        {'hookRVA': 0x2ee12, 'stolen': '8b4514a802', 'caveRVA': 0x6b2fe, 'caveSize': 3330,
         'resume': 0x2ee17, 'wm': 'esi', 'load_path': -0x3c,
         'payload': 'b4c697ba396ecb59125c505666ad3465d1208b8a1e3e53a0c457657b341376b9',
         'exports': {'LdrGetDllHandle': 0x7bc2a6b0, 'LdrLoadDll': 0x7bc286d0,
                     'NtProtectVirtualMemory': 0x7bc4d020, 'NtOpenFile': 0x7bc4ce50,
                     'NtReadFile': 0x7bc4cb80, 'NtClose': 0x7bc4cc10}},
    '7823d71fbce6c9947163bf8b96beb299eabb02878245bcaf6759f2a22e81f071':
        {'caveRVA': 0xf1185, 'caveSize': 61051,
         'sites': [{'hookRVA': 0x48004, 'stolen': '1f2003d5', 'resume': 0x48008,
                    'wm': 'x27', 'load_path': -0x98},
                   {'hookRVA': 0xa71bc, 'stolen': '1f2003d5', 'resume': 0xa71c0,
                    'wm': 'x22', 'load_path': -0x88}],
         'guest': {'LdrLoadDll': 0x9f698, 'LdrGetDllHandle': 0x9f698,
                   'NtProtectVirtualMemory': 0xea8cc},
         'payload': 'bee4ee13c235bd5de3cb6ce840b9695effd5623132f6dc0d137496d6a5330f5e',
         'exports': {'LdrGetDllHandle': 0x180043328, 'LdrLoadDll': 0x180040e94,
                     'NtProtectVirtualMemory': 0x180065db0}},
}
EXPORTS = ['LdrGetDllHandle', 'LdrLoadDll', 'NtProtectVirtualMemory',
           'NtOpenFile', 'NtReadFile', 'NtClose']
PROLOGUES = [rb'\x55\x89\xe5', rb'\x55\x8b\xec']
NOP64 = bytes.fromhex('1f2003d5')

SUBREG = {'al': 'eax', 'ah': 'eax', 'ax': 'eax', 'bl': 'ebx', 'bh': 'ebx', 'bx': 'ebx',
          'cl': 'ecx', 'ch': 'ecx', 'cx': 'ecx', 'dl': 'edx', 'dh': 'edx', 'dx': 'edx',
          'si': 'esi', 'di': 'edi', 'bp': 'ebp', 'sp': 'esp'}


class PE:
    def __init__(self, path):
        self.path = path
        self.d = open(path, 'rb').read()
        e = struct.unpack_from('<I', self.d, 0x3c)[0]
        self.machine = struct.unpack_from('<H', self.d, e + 4)[0]
        nsec = struct.unpack_from('<H', self.d, e + 6)[0]
        optsz = struct.unpack_from('<H', self.d, e + 20)[0]
        self.opt = e + 24
        self.magic = struct.unpack_from('<H', self.d, self.opt)[0]
        wide = self.magic == 0x20b
        self.imagebase = (struct.unpack_from('<Q', self.d, self.opt + 24)[0] if wide
                          else struct.unpack_from('<I', self.d, self.opt + 28)[0])
        self.salign = struct.unpack_from('<I', self.d, self.opt + 32)[0]
        self.secs = []
        self.hdr_off = {}
        self.flags = {}
        for i in range(nsec):
            o = e + 24 + optsz + i * 40
            name = self.d[o:o + 8].rstrip(b'\0').decode('latin1')
            vsize, vrva, rsize, roff = struct.unpack_from('<IIII', self.d, o + 8)
            if roff:
                self.secs.append((name, vrva, vsize, roff, rsize))
                self.hdr_off[name] = o
                self.flags[name] = struct.unpack_from('<I', self.d, o + SECTION_CHARACTERISTICS_OFFSET)[0]
        self.dirs = self.opt + (112 if wide else 96)

    def sec(self, prefix):
        for s in self.secs:
            if s[0].startswith(prefix):
                return s
        raise SystemExit(f"{self.path}: no {prefix} section")

    def off(self, rva):
        for _, vrva, vsize, roff, rsize in self.secs:
            if vrva <= rva < vrva + max(vsize, rsize):
                return roff + (rva - vrva)
        raise SystemExit(f"{self.path}: rva {rva:#x} not mapped")

    def text(self):
        _, vrva, _, roff, rsize = self.sec('.text')
        return vrva, self.d[roff:roff + rsize]

    def cs(self):
        if self.machine == 0xaa64:
            md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
        else:
            md = capstone.Cs(capstone.CS_ARCH_X86,
                             capstone.CS_MODE_64 if self.machine == 0x8664 else capstone.CS_MODE_32)
        md.detail = True
        return md

    def pdata_starts(self):
        _, _, _, proff, prsize = self.sec('.pdata')
        stride = 8 if self.machine == 0xaa64 else 12
        out = {struct.unpack_from('<I', self.d, o)[0] for o in range(proff, proff + prsize, stride)}
        return sorted(out - {0})

    def exports(self):
        edir = struct.unpack_from('<I', self.d, self.dirs)[0]
        o = self.off(edir)
        nnames = struct.unpack_from('<I', self.d, o + 0x18)[0]
        afun, anam, aord = struct.unpack_from('<III', self.d, o + 0x1c)
        fo, no, oo = self.off(afun), self.off(anam), self.off(aord)
        out = {}
        for i in range(nnames):
            nrva = struct.unpack_from('<I', self.d, no + 4 * i)[0]
            ordn = struct.unpack_from('<H', self.d, oo + 2 * i)[0]
            frva = struct.unpack_from('<I', self.d, fo + 4 * ordn)[0]
            s = self.off(nrva)
            out[self.d[s:self.d.index(b'\0', s)].decode('latin1')] = frva
        return out

    def cave(self):
        def tail(s):
            name, vrva, vsize, roff, rsize = s
            mapped = -(-vsize // self.salign) * self.salign
            return {'caveRVA': vrva + vsize, 'caveSize': max(min(rsize, mapped) - vsize, 0),
                    'fill': self.d[roff + vsize] if rsize > vsize else 0, 'caveSection': name}
        text = tail(self.sec('.text'))
        if payload_slot(text)[1] >= PAYLOAD[self.machine]:
            return text
        ro = [tail(s) for s in self.secs
              if not self.flags[s[0]] & (IMAGE_SCN_MEM_DISCARDABLE | IMAGE_SCN_MEM_WRITE)]
        return max(ro, key=lambda t: t['caveSize'])

    def string_refs(self, name):
        _, rvrva, _, rroff, rrsize = self.sec('.rdata')
        k = self.d[rroff:rroff + rrsize].find(name.encode() + b'\0')
        if k == -1:
            raise SystemExit(f"{self.path}: no {name} string; not a traced wine build")
        srva = rvrva + k
        tvrva, text = self.text()
        if self.machine == 0x14c:
            pat = re.escape(struct.pack('<I', self.imagebase + srva))
            return srva, [tvrva + m.start() for m in re.finditer(pat, text)]
        hits = []
        for i in self.cs().disasm(text, tvrva):
            for op in i.operands:
                if op.type == X86.X86_OP_MEM and op.mem.base == X86.X86_REG_RIP:
                    if i.address + i.size + op.mem.disp == srva:
                        hits.append(i.address)
        return srva, hits

    def func_start(self, before):
        tvrva, text = self.text()
        best = None
        for pat in PROLOGUES:
            for m in re.finditer(pat, text[:before - tvrva]):
                if best is None or m.start() > best:
                    best = m.start()
        if best is None:
            raise SystemExit(f"{self.path}: no prologue before {before:#x}")
        return tvrva + best


def steal(insns, k, need=5):
    taken, total = [], 0
    while total < need:
        taken.append(insns[k + len(taken)])
        total += taken[-1].size
    return taken, total


def resolve_amd64(pe):
    md = pe.cs()
    tvrva, text = pe.text()
    insns = list(md.disasm(text, tvrva))

    _, pvrva, pvsize, proff, _ = pe.sec('.pdata')
    funcs = []
    for o in range(proff, proff + pvsize, 12):
        begin, end, _ = struct.unpack_from('<III', pe.d, o)
        if begin:
            funcs.append((begin, end))

    owner = {}
    for name in ('build_module', 'alloc_module'):
        _, refs = pe.string_refs(name)
        for r in refs:
            for begin, end in funcs:
                if begin <= r < end:
                    owner.setdefault(name, (begin, end))
    bm = owner['build_module']
    am = owner['alloc_module'][0]

    body = [i for i in insns if bm[0] <= i.address < bm[1]]
    calls = [k for k, i in enumerate(body) if i.mnemonic == 'call' and i.op_str == hex(am)]
    if len(calls) != 1:
        raise SystemExit(f"{pe.path}: {len(calls)} alloc_module calls in build_module, want 1")

    k, wm = calls[0] + 1, None
    while True:
        i = body[k]
        if i.mnemonic == 'test' and i.op_str == 'rax, rax':
            k += 1
        elif i.mnemonic == 'mov' and i.op_str.endswith(', rax'):
            wm = i.op_str.split(',')[0].strip()
            k += 1
        elif i.mnemonic in ('je', 'jz'):
            k += 1
        else:
            break
    hook = body[k]
    slot = amd64_load_path(pe, body, hook.address)
    return {'build_module': bm, 'alloc_module': am, 'wm': wm, 'load_path': slot,
            'hookRVA': hook.address, 'stolen': hook.bytes.hex(), 'insn': f"{hook.mnemonic} {hook.op_str}"}


def amd64_load_path(pe, body, hook):
    src, slot, stored_at = 'rcx', None, None
    for i in body:
        if i.address >= hook:
            break
        if i.mnemonic != 'mov' or ',' not in i.op_str:
            continue
        dst, rhs = (x.strip() for x in i.op_str.split(',', 1))
        if rhs != src:
            continue
        if dst.startswith('qword ptr [rsp'):
            slot = 0 if '+' not in dst else int(dst.split('+')[1].strip().rstrip(']'), 16)
            stored_at = i.address
            break
        if re.fullmatch(r'r[a-z0-9]+', dst):
            src = dst
    if slot is None:
        raise SystemExit(f"{pe.path}: load_path never reaches the frame in build_module")

    for i in body:
        if not stored_at < i.address < hook:
            continue
        if i.mnemonic in ('push', 'pop') or (i.mnemonic in ('sub', 'add') and i.op_str.startswith('rsp,')):
            raise SystemExit(f"{pe.path}: rsp moves at {i.address:#x}, load_path slot not rsp-stable")
        if i.mnemonic == 'mov' and i.op_str.startswith(f'qword ptr [rsp + {slot:#x}],'):
            raise SystemExit(f"{pe.path}: load_path slot rewritten at {i.address:#x}")
    return slot


def resolve_i386(pe):
    md = pe.cs()
    tvrva, _ = pe.text()
    _, refs = pe.string_refs('build_module')
    start = pe.func_start(min(refs))
    body = list(md.disasm(pe.d[pe.off(start):pe.off(start) + 0x1400], start))

    anchor = None
    for k, i in enumerate(body):
        if i.mnemonic == 'test' and re.match(r'^byte ptr \[e\w\w \+ 0x37\], 1$', i.op_str):
            anchor = k
            break
    if anchor is None:
        raise SystemExit(f"{pe.path}: no MODREF flag test in build_module")
    wm = re.search(r'\[(e\w\w) \+ 0x37\]', body[anchor].op_str).group(1)

    gate = None
    for k in range(anchor - 1, max(anchor - 24, 0), -1):
        i = body[k]
        if i.mnemonic == 'test' and i.operands and i.operands[-1].type == X86.X86_OP_IMM \
                and i.operands[-1].imm in (1, 2):
            gate = k
            break
    if gate is None:
        raise SystemExit(f"{pe.path}: no module-flags gate above the MODREF flag test")
    hook_k = gate
    tested = body[gate].operands[0]
    if tested.type == X86.X86_OP_REG:
        want = SUBREG.get(body[gate].reg_name(tested.reg), body[gate].reg_name(tested.reg))
        for k in range(gate - 1, max(gate - 8, -1), -1):
            i = body[k]
            if i.mnemonic != 'mov' or i.operands[0].type != X86.X86_OP_REG:
                continue
            if SUBREG.get(i.reg_name(i.operands[0].reg), i.reg_name(i.operands[0].reg)) == want:
                hook_k = k
                break
        else:
            raise SystemExit(f"{pe.path}: {want} tested at {body[gate].address:#x} with no load above")
    holder = body[gate] if tested.type != X86.X86_OP_REG else body[hook_k]
    mem = [o for o in holder.operands if o.type == X86.X86_OP_MEM]
    if len(mem) != 1:
        raise SystemExit(f"{pe.path}: {holder.address:#x} does not read the flags from memory")
    flags_slot = mem[0].mem.disp

    taken, total = steal(body, hook_k)

    jk = None
    for k in range(gate + 1, min(gate + 8, len(body))):
        if body[k].mnemonic in ('jne', 'jnz'):
            jk = k
            break
        if X86.X86_REG_EFLAGS in body[k].regs_access()[1]:
            break
    if jk is None:
        raise SystemExit(f"{pe.path}: no branch on the module-flags gate at {body[gate].address:#x}")
    skip = body[jk].operands[0].imm
    stole_branch = taken[-1].address == body[jk].address

    load_path = None
    for i in body[anchor:anchor + 12]:
        if i.mnemonic == 'mov' and i.op_str.startswith('edx, dword ptr [ebp'):
            m = re.search(r'ebp ([-+]) (0x[0-9a-f]+)', i.op_str)
            load_path = int(m.group(2), 16) * (-1 if m.group(1) == '-' else 1)
        if i.mnemonic == 'call':
            break
    return {'build_module': (start, None), 'wm': wm, 'hookRVA': taken[0].address,
            'stolen': b''.join(i.bytes for i in taken).hex(), 'stolen_len': total,
            'insn': ' ; '.join(f"{i.mnemonic} {i.op_str}" for i in taken),
            'load_path': load_path, 'skip': skip, 'stole_branch': stole_branch,
            'stolen_head': b''.join(i.bytes for i in (taken[:-1] if stole_branch else taken)).hex(),
            'flags_slot': flags_slot, 'gate_bit': body[gate].operands[-1].imm}


def aarch64_walk(md, text, tv):

    off = 0
    while off < len(text):
        last = None
        for i in md.disasm(text[off:], tv + off):
            last = i
            yield i
        off = (last.address + last.size - tv + 4) if last else off + 4


def aarch64_literal_refs(pe, names):
    _, rvrva, _, rroff, rrsize = pe.sec('.rdata')
    blob = pe.d[rroff:rroff + rrsize]
    want = {}
    for name in names:
        pat = name.encode() + b'\0'
        k = blob.find(pat)
        while k != -1:
            if k == 0 or blob[k - 1] == 0:
                want[rvrva + k] = name
            k = blob.find(pat, k + 1)
    tv, text = pe.text()
    out, pages = {}, {}
    for i in aarch64_walk(pe.cs(), text, tv):
        if i.mnemonic == 'adrp':
            pages[i.operands[0].reg] = i.operands[1].imm
        elif i.mnemonic == 'add' and len(i.operands) == 3 \
                and i.operands[2].type == A64.ARM64_OP_IMM:
            page = pages.get(i.operands[1].reg)
            srva = None if page is None else page + i.operands[2].imm
            if srva in want:
                out.setdefault(srva, (want[srva], []))[1].append(i.address)
    return out


def aarch64_body(pe, md, lo, hi):
    tv, text = pe.text()
    lo, hi = max(tv, lo) & ~3, min(tv + len(text), hi)
    return list(aarch64_walk(md, text[lo - tv:hi - tv], lo))


def aarch64_open(pe, md, inside):
    body = aarch64_body(pe, md, inside - 0x4000, inside + 4)
    for k in range(len(body) - 1, -1, -1):
        i = body[k]
        if i.mnemonic == 'sub' and i.op_str.startswith('sp, sp, #') \
                and any(n.mnemonic == 'add' and n.op_str.startswith('x29, sp, #')
                        for n in body[k + 1:k + 13]):
            return i.address
    raise SystemExit(f"{pe.path}: no frame prologue above {inside:#x}")


def aarch64_hook(pe, md, ref, allocs):
    start = aarch64_open(pe, md, ref)
    body = aarch64_body(pe, md, start, start + 0x2000)

    def name(i, n):
        return i.reg_name(i.operands[n].reg)

    call = next((k for k, i in enumerate(body)
                 if i.mnemonic == 'bl' and i.operands[0].imm in allocs), None)
    if call is None:
        raise SystemExit(f"{pe.path}: build_module at {start:#x} never calls alloc_module")
    if body[call + 1].mnemonic != 'cbz' or name(body[call + 1], 0) != 'x0':
        raise SystemExit(f"{pe.path}: alloc_module at {body[call].address:#x} is not null-checked")
    join = next((i.operands[1].imm for i in body[call + 2:call + 10] if i.mnemonic == 'cbz'), None)
    if join is None:
        raise SystemExit(f"{pe.path}: no id test below alloc_module at {body[call].address:#x}")
    k = next((k for k, i in enumerate(body) if i.address == join), None)
    if k is None or body[k].bytes != NOP64:
        raise SystemExit(f"{pe.path}: the id block from {body[call].address:#x} joins on "
                         f"{join:#x}, which is not a nop")

    for i in body[call + 1:k]:
        if 'x0' in {i.reg_name(w).replace('w', 'x', 1) for w in i.regs_access()[1]}:
            raise SystemExit(f"{pe.path}: x0 no longer the MODREF at {i.address:#x}")
    wm = next((name(i, 0) for i in body[call + 1:k] if i.mnemonic == 'mov'
               and i.operands[1].type == A64.ARM64_OP_REG and name(i, 1) == 'x0'), None)
    if wm is None or not any(i.mnemonic == 'add' and i.op_str.endswith('#0x118')
                             and name(i, 1) == wm for i in body[call:k]):
        raise SystemExit(f"{pe.path}: nothing below {body[call].address:#x} treats the result "
                         f"as a MODREF")

    def spill(src):
        for i in body[:24]:
            if i.mnemonic == 'stur' and name(i, 0) == src \
                    and i.operands[1].type == A64.ARM64_OP_MEM \
                    and i.reg_name(i.operands[1].mem.base) == 'fp':
                return i.operands[1].mem.disp
        raise SystemExit(f"{pe.path}: build_module at {start:#x} never spills {src}")

    return {'build_module': start, 'hookRVA': join, 'stolen': NOP64.hex(), 'stolen_len': 4,
            'insn': f"{body[k].mnemonic} {body[k].op_str}".strip(), 'resume': join + 4,
            'wm': wm, 'load_path': spill('x0'), 'flags_slot': spill('w5')}


def aarch64_guest_syscall(pe, md, native):
    num = next((int(i.op_str.split('#')[1], 0)
                for i in aarch64_body(pe, md, native, native + 8)
                if i.mnemonic == 'mov' and i.op_str.startswith('x8, #')), None)
    if num is None:
        raise SystemExit(f"{pe.path}: no syscall number at {native:#x}")
    tv, text = pe.text()
    pat = b'\x4c\x8b\xd1\xb8' + num.to_bytes(4, 'little')
    k = text.find(pat)
    if k < 0 or text.find(pat, k + 1) >= 0:
        raise SystemExit(f"{pe.path}: guest stub for syscall {num:#x} is "
                         f"{'missing' if k < 0 else 'not unique'}")
    stub = tv + k
    body = list(aarch64_walk(md, text, tv))
    found = set()
    for n, i in enumerate(body[:-1]):
        nx = body[n + 1]
        if i.mnemonic != 'adrp' or not i.op_str.startswith('x11, '):
            continue
        if nx.mnemonic != 'add' or not nx.op_str.startswith('x11, x11, #'):
            continue
        if int(i.op_str.split('#')[1], 0) + int(nx.op_str.split('#')[1], 0) != stub:
            continue
        entry = i.address - 8
        head = aarch64_body(pe, md, entry, entry + 4)
        if head and head[0].mnemonic == 'str' and head[0].op_str.startswith('x30, [sp, #-'):
            found.add(entry)
    if not found:
        raise SystemExit(f"{pe.path}: no guest thunk tail branching to {stub:#x}")
    return found


def aarch64_twin(pe, md, native, span):

    want = [i.mnemonic for i in aarch64_body(pe, md, native, native + 0x100)]
    tv, text = pe.text()
    lo, hi = span
    opener = text[native - tv:native - tv + 4]
    hits, k = [], text.find(opener, lo - tv, hi - tv)
    while k != -1:
        f = tv + k
        if f != native and [i.mnemonic for i in aarch64_body(pe, md, f, f + 0x100)] == want:
            hits.append(f)
        k = text.find(opener, k + 4, hi - tv)
    if len(hits) != 1:
        raise SystemExit(f"{pe.path}: {len(hits)} twins of {native:#x} in {lo:#x}..{hi:#x}")
    return hits[0]


def resolve_aarch64(pe):
    md = pe.cs()
    refs = aarch64_literal_refs(pe, ('build_module', 'alloc_module'))
    allocs = {aarch64_open(pe, md, a[0]) for n, a in refs.values() if n == 'alloc_module'}
    sites = sorted((aarch64_hook(pe, md, a[0], allocs)
                    for n, a in refs.values() if n == 'build_module'),
                   key=lambda s: s['hookRVA'])
    if len(sites) != 2:
        raise SystemExit(f"{pe.path}: {len(sites)} build_module copies, shim64.S hooks two")

    ex = pe.exports()
    thunks = aarch64_guest_syscall(pe, md, ex['NtProtectVirtualMemory'])

    def calls(s):
        bm = s['build_module']
        return {int(i.op_str.lstrip('#'), 0)
                for i in aarch64_body(pe, md, bm, bm + 0x1000) if i.mnemonic == 'bl'}

    reach = [calls(s) for s in sites]
    guest = [(s, c & thunks) for s, c in zip(sites, reach)
             if c & thunks and ex['NtProtectVirtualMemory'] not in c]
    native = [s for s, c in zip(sites, reach)
              if ex['NtProtectVirtualMemory'] in c and not c & thunks]
    if len(guest) != 1 or len(native) != 1 or guest[0][0] is native[0]:
        raise SystemExit(f"{pe.path}: cannot tell the two build_module copies apart by their "
                         f"route to NtProtectVirtualMemory")
    if len(guest[0][1]) != 1:
        raise SystemExit(f"{pe.path}: guest build_module reaches {len(guest[0][1])} protect thunks")
    thunk = guest[0][1].pop()

    bm = guest[0][0]['build_module']
    tv, text = pe.text()
    span = (max(tv, bm - 0x10000), min(tv + len(text), bm + 0x10000))
    load = aarch64_twin(pe, md, ex['LdrLoadDll'], span)
    return dict(sites[0], sites=sites,
                guest={'LdrLoadDll': load, 'LdrGetDllHandle': load,
                       'NtProtectVirtualMemory': thunk})


def resolve(path):
    pe = PE(path)
    r = (resolve_aarch64(pe) if pe.machine == 0xaa64 else
         resolve_amd64(pe) if pe.machine == 0x8664 else resolve_i386(pe))
    r.update(pe.cave())
    r['machine'], r['magic'], r['imageBase'] = pe.machine, pe.magic, pe.imagebase
    ex = pe.exports()
    r['exports'] = {n: pe.imagebase + ex[n] for n in EXPORTS if n in ex}
    r['resume'] = r['hookRVA'] + len(r['stolen']) // 2
    r['sha256'] = hashlib.sha256(pe.d).hexdigest()
    return r


def report(path):
    machine = PE(path).machine
    if machine not in ARCH:
        print(f"{path}\n  machine {machine:#x} carries no detour, skipped\n")
        return True
    r = resolve(path)
    pin = PINNED.get(r['sha256'], {})
    arch = ARCH[machine]
    print(f"{path}\n  arch {arch}  machine {r['machine']:#x}  magic {r['magic']:#x}"
          f"  imageBase {r['imageBase']:#x}\n  sha256 {r['sha256']}"
          f"{'  (the pinned build, self-testing)' if pin else '  (not a pinned build)'}")
    ok = True

    def line(label, got, key=None, fmt=lambda v: f"{v:#x}", want=pin):
        nonlocal ok
        tag = ""
        if key and key in want:
            match = want[key] == got
            ok = ok and match
            tag = "  MATCH" if match else f"  MISMATCH (pinned {fmt(want[key])})"
        print(f"  {label:13} {fmt(got)}{tag}")

    sites = r.get('sites')
    pinned_sites = pin.get('sites') or []
    for n, s in enumerate(sites or [r], 1):
        want = pin
        if sites:
            want = pinned_sites[n - 1] if n <= len(pinned_sites) else {}
            print(f"  hook {n} of {len(sites)}, build_module at {s['build_module']:#x}")
        line('hookRVA', s['hookRVA'], 'hookRVA', want=want)
        print(f"  {'insn':13} {s['insn']}")
        line('stolen', s['stolen'], 'stolen', fmt=str, want=want)
        line('resume', s['resume'], 'resume', want=want)
        line('wm', s['wm'], 'wm', fmt=str, want=want)
        if s.get('load_path') is not None:
            frame = {0x8664: 'rsp', 0x14c: 'ebp', 0xaa64: 'x29'}[machine]
            slot = ((lambda v: f"{frame}+{v:#x}") if machine == 0x8664
                    else (lambda v: f"{frame}{v:+#x}"))
            line('load_path', s['load_path'], 'load_path', fmt=slot, want=want)
    line('caveRVA', r['caveRVA'], 'caveRVA')
    line('caveSize', r['caveSize'], 'caveSize', fmt=str)
    need = PAYLOAD[r['machine']]
    print(f"  {'cave fill':13} {r['fill']:#02x}   room {r['caveSize']} bytes, payload {need}"
          f" -> {'fits' if r['caveSize'] >= need else 'TOO SMALL'}")
    def table(items, want):
        nonlocal ok
        for n, va in items.items():
            pinned_va = want.get(n)
            tag = ""
            if pinned_va:
                match = pinned_va == va
                ok = ok and match
                tag = "  MATCH" if match else f"  MISMATCH (pinned {pinned_va:#x})"
            print(f"    {n:24} {va:#x}{tag}")

    table(r['exports'], pin.get('exports', {}))
    if r.get('guest'):
        print("  guest loader, which is what link64.ld resolves instead")
        table(r['guest'], pin.get('guest', {}))
    if pin:
        print(f"  self-test: {'all pinned values reproduced' if ok else 'FAILED'}")
    print()
    return ok if pin else True


def ntdlls(arg):
    p = pathlib.Path(arg)
    if p.is_file():
        return [str(p)]
    for root in (p / 'Contents/SharedSupport/CrossOver/lib/wine', p / 'lib/wine', p):
        archs = sorted(d for d in root.glob('*-windows') if d.is_dir())
        if not archs:
            continue
        found = []
        for d in archs:
            for name in ('ntdll.dll.steambridge-orig', 'ntdll.dll'):
                if (d / name).is_file():
                    found.append(str(d / name))
                    break
        if found:
            return found
    raise SystemExit(f"{arg}: no <arch>-windows/ntdll.dll under it")


def payload_slot(cave):
    payload = (cave['caveRVA'] + 15) & ~15
    return payload, cave['caveSize'] - (payload - cave['caveRVA'])


def shell_vars(path):
    r = resolve(path)
    payload, room = payload_slot(r)
    need = PAYLOAD[r['machine']]
    if room < need:
        raise SystemExit(f"{path}: cave has {room} bytes at {payload:#x}, payload needs {need}")
    scratch = 'rsi' if r['wm'] == 'rbx' else 'rbx'
    out = {
        'SB_ARCH': ARCH[r['machine']], 'SB_MACHINE': f"{r['machine']:#x}",
        'SB_MAGIC': f"{r['magic']:#x}", 'SB_IMAGEBASE': f"{r['imageBase']:#x}",
        'SB_SHA256': r['sha256'],
        'SB_HOOK_RVA': f"{r['hookRVA']:#x}", 'SB_STOLEN': r['stolen'],
        'SB_STOLEN_BYTES': ','.join(f"0x{b:02x}" for b in bytes.fromhex(r['stolen'])),
        'SB_STOLEN_LEN': str(len(r['stolen']) // 2),
        'SB_RESUME_VA': f"{r['imageBase'] + r['resume']:#x}",
        'SB_WM': r['wm'], 'SB_SCRATCH': scratch,
        'SB_LOAD_PATH': f"{r['load_path']:#x}" if r.get('load_path') is not None else '',
        'SB_CAVE_RVA': f"{r['caveRVA']:#x}", 'SB_CAVE_SIZE': str(r['caveSize']),
        'SB_PAYLOAD_RVA': f"{payload:#x}", 'SB_PAYLOAD_VA': f"{r['imageBase'] + payload:#x}",
        'SB_CAVE_ROOM': str(room), 'SB_FILL': f"{r['fill']:#04x}",
        'SB_CAVE_SECTION': r['caveSection'],
    }
    if PINNED.get(r['sha256'], {}).get('payload'):
        out['SB_PAYLOAD_SHA256'] = PINNED[r['sha256']]['payload']
    if r.get('skip') is not None:
        out['SB_SKIP_VA'] = f"{r['imageBase'] + r['skip']:#x}"
        out['SB_STOLE_BRANCH'] = '1' if r['stole_branch'] else ''
        out['SB_STOLEN_HEAD_BYTES'] = ','.join(
            f"0x{b:02x}" for b in bytes.fromhex(r['stolen_head']))
        out['SB_FLAGS_SLOT'] = ('%#x' if r['flags_slot'] >= 0 else '-%#x') % abs(r['flags_slot'])
        if r.get('gate_bit') is not None:
            out['SB_GATE_BIT'] = f"{r['gate_bit']:#x}"

    for n, s in enumerate(r.get('sites') or [], 1):
        out[f'SB_HOOK_RVA_{n}'] = f"{s['hookRVA']:#x}"
        out[f'SB_STOLEN_{n}'] = s['stolen']
        out[f'SB_RESUME_VA_{n}'] = f"{r['imageBase'] + s['resume']:#x}"
        out[f'SB_LOAD_PATH_{n}'] = f"{s['load_path']:#x}"
    if r.get('sites'):
        out['SB_SITES'] = str(len(r['sites']))

    for n, va in r['exports'].items():
        out['SB_' + re.sub(r'(?<!^)(?=[A-Z])', '_', n).upper()] = f"{va:#x}"
    for n, rva in (r.get('guest') or {}).items():
        out['SB_' + re.sub(r'(?<!^)(?=[A-Z])', '_', n).upper()] = f"{r['imageBase'] + rva:#x}"
    return out


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(f"usage: {sys.argv[0]} [--sh] <CrossOver bundle | wine dir | ntdll.dll> ...")
    if sys.argv[1] == '--sh':
        if len(sys.argv) != 3:
            raise SystemExit("--sh takes one ntdll.dll")
        for k, v in shell_vars(sys.argv[2]).items():
            print(f"{k}='{v}'")
        sys.exit(0)
    paths = [p for arg in sys.argv[1:] for p in ntdlls(arg)]
    sys.exit(0 if all([report(p) for p in paths]) else 1)
