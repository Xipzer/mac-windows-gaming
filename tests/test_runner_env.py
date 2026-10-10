import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
RUNNER_ENV = REPO / 'notproton/runner.env'
SHOWN = ('WINEDLLPATH_D9VK',)


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
        self.bin.mkdir()

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


if __name__ == '__main__':
    unittest.main(verbosity=2)
