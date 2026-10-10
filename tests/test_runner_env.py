import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
RUNNER_ENV = REPO / 'notproton/runner.env'
SHOWN = ('WINEDLLPATH_D9VK', 'NOTPROTON_RETINA', 'WINEDLLOVERRIDES')
BUILTIN = b'MZ' + bytes(62) + b'Wine builtin DLL' + bytes(64)
NATIVE = b'MZ' + bytes(62) + b'\x0e\x1f\xba\x0e\x00\xb4\x09\xcd!This program' + bytes(64)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, str):
        path.write_text(data)
    else:
        path.write_bytes(data)
    return path


def tree(root):
    return {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in root.rglob('*') if p.is_file()}


def uncompressed_cab(members):
    data, entries = b''.join(members.values()), b''
    for name, body in members.items():
        entries += struct.pack('<IIHHHH', len(body), data.index(body), 0, 0x5021, 0, 0x20) + name.encode() + b'\0'
    files_at = 36 + 8
    data_at = files_at + len(entries)
    block = struct.pack('<IHH', 0, len(data), len(data)) + data
    header = struct.pack('<4sIIIIIBBHHHHH', b'MSCF', 0, data_at + len(block), 0, files_at, 0, 3, 1, 1, len(members), 0, 0, 0)
    return header + struct.pack('<IHH', data_at, 1, 0) + entries + block


class RunnerEnv(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.runner = self.root / 'runner'
        self.data = self.root / 'compatdata/10'
        self.win = self.data / 'pfx/drive_c/windows'
        write(self.win / 'syswow64/d3dx9_43.dll', BUILTIN)
        write(self.win / 'syswow64/d3dcompiler_43.dll', NATIVE)
        (self.win / 'system32').mkdir()
        self.game = self.root / 'game'
        redist = self.game / 'redist/DirectX'
        write(redist / 'Jun2010_d3dx9_43_x86.cab', uncompressed_cab({'d3dx9_43.dll': b'native x86 d3dx9'}))
        write(redist / 'Jun2010_d3dx9_43_x64.cab', uncompressed_cab({'d3dx9_43.dll': b'native x64 d3dx9'}))
        write(redist / 'Jun2010_D3DCompiler_43_x86.cab', uncompressed_cab({'D3DCompiler_43.dll': b'newer compiler'}))
        write(redist / 'Jun2010_xinput_x86.cab', uncompressed_cab({'xinput1_3.dll': b'xinput'}))
        self.bin = self.root / 'bin'
        write(self.bin / 'osascript', '#!/bin/sh\necho "${STUB_SCALE-2}"\n').chmod(0o755)

    def source(self, **env):
        env = {'HOME': str(self.root), 'PATH': f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin',
               'CX_ROOT': str(self.runner), 'STEAM_COMPAT_DATA_PATH': str(self.data),
               'STEAM_COMPAT_INSTALL_PATH': str(self.game), 'WINEDLLOVERRIDES': 'user=b', **env}
        show = ''.join(f'echo "{name}=${{{name}-}}"; ' for name in SHOWN)
        out = subprocess.run(['sh', '-c', f'set -e; verb=waitforexitandrun; . "$1"; {show}', 'sh', str(RUNNER_ENV)],
                             env=env, capture_output=True, text=True, check=True).stdout
        return dict(line.split('=', 1) for line in out.splitlines())

    def test_dxvk_only_with_a_resolvable_vulkan_driver(self):
        d9vk = self.runner / 'Frameworks/renderer/d9vk/wine'
        d9vk.mkdir(parents=True)
        self.assertEqual(self.source()['WINEDLLPATH_D9VK'], '', 'no Vulkan driver, so wined3d keeps Direct3D 9')
        write(self.runner / 'Resources/vulkan/icd.d/kosmickrisp_mesa_icd.json', '{}')
        self.assertEqual(self.source()['WINEDLLPATH_D9VK'], str(d9vk))

    def test_retina_follows_the_main_screen_unless_a_launch_option_sets_it(self):
        self.assertEqual(self.source(STUB_SCALE='1')['NOTPROTON_RETINA'], '0', '1x main screen')
        self.assertEqual(self.source(STUB_SCALE='2')['NOTPROTON_RETINA'], '', '2x main screen keeps the run script default')
        self.assertEqual(self.source(STUB_SCALE='1', NOTPROTON_RETINA='1')['NOTPROTON_RETINA'], '1')

    def test_directx_cabs_replace_only_wine_builtins_once(self):
        self.assertEqual(self.source()['WINEDLLOVERRIDES'], 'd3dx9_43=n,b;user=b')
        self.assertEqual((self.win / 'syswow64/d3dx9_43.dll').read_bytes(), b'native x86 d3dx9')
        self.assertEqual((self.win / 'syswow64/d3dx9_43.dll.notproton-orig').read_bytes(), BUILTIN)
        self.assertEqual((self.win / 'system32/d3dx9_43.dll').read_bytes(), b'native x64 d3dx9')
        self.assertEqual((self.win / 'syswow64/d3dcompiler_43.dll').read_bytes(), NATIVE, 'a native DLL is kept')
        self.assertFalse((self.win / 'syswow64/xinput1_3.dll').exists(), 'only d3dx9 and d3dcompiler cabs')

        before = tree(self.root)
        self.assertEqual(self.source()['WINEDLLOVERRIDES'], 'd3dx9_43=n,b;user=b')
        self.assertEqual(tree(self.root), before, 'the second launch unpacked again')

    def test_a_prefix_wine_has_not_built_yet_waits_for_a_later_launch(self):
        shutil.rmtree(self.win / 'syswow64')
        self.assertEqual(self.source()['WINEDLLOVERRIDES'], 'user=b')
        self.assertFalse((self.data / 'notproton-directx').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
