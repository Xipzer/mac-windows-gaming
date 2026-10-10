import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
RUNNER_ENV = REPO / 'notproton/runner.env'
SHOWN = ('WINEDLLPATH_D9VK', 'NOTPROTON_RETINA')


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, str):
        path.write_text(data)
    else:
        path.write_bytes(data)
    return path


class RunnerEnv(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.runner = self.root / 'runner'
        self.bin = self.root / 'bin'
        write(self.bin / 'osascript', '#!/bin/sh\necho "${STUB_SCALE-2}"\n').chmod(0o755)

    def source(self, **env):
        env = {'HOME': str(self.root), 'PATH': f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin',
               'CX_ROOT': str(self.runner), **env}
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


if __name__ == '__main__':
    unittest.main(verbosity=2)
