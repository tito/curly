# -*- coding: utf-8 -*-

import sys
from os import environ, getenv
from os.path import join, isdir
try:
    from setuptools import setup, Extension
except ImportError:
    from distutils.core import setup
    from distutils.extension import Extension


def pkgconfig(*packages, **kw):
    flag_map = {'-I': 'include_dirs', '-L': 'library_dirs', '-l': 'libraries'}
    lenviron = None
    pconfig = join(sys.prefix, 'libs', 'pkgconfig')

    if isdir(pconfig):
        lenviron = environ.copy()
        lenviron['PKG_CONFIG_PATH'] = '{};{}'.format(
            environ.get('PKG_CONFIG_PATH', ''), pconfig)
    cmd = 'pkg-config --libs --cflags {}'.format(' '.join(packages))
    results = getoutput(cmd, lenviron).split()
    for token in results:
        ext = token[:2].decode('utf-8')
        flag = flag_map.get(ext)
        if not flag:
            continue
        kw.setdefault(flag, []).append(token[2:].decode('utf-8'))
    return kw


def getoutput(cmd, env=None):
    import subprocess
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, env=env)
    p.wait()
    if p.returncode:  # if not returncode == 0
        print('WARNING: A problem occurred while running {0} (code {1})\n'
              .format(cmd, p.returncode))
        stderr_content = p.stderr.read()
        if stderr_content:
            print('{0}\n'.format(stderr_content))
        return ""
    return p.stdout.read()


# version
with open(join("curly", "__init__.py")) as fd:
    versionline = [x for x in fd.readlines() if x.startswith("__version__")]
    VERSION = versionline[0].split('"')[-2]


FILES = [
    'curly/_curly.pyx',
    'curly/_include.pxi',
    'curly/_queue.pxi',
]

LIBRARIES = []
LIBRARY_DIRS = []
LIB_LOCATION = None
EXTRA_LINK_ARGS = []
INCLUDE_DIRS = []
INSTALL_REQUIRES = []
SETUP_KWARGS = {
    "name": "curly",
    "version": VERSION,
    "packages": ["curly"],
    "py_modules": ["setup"],
    "ext_package": "curly",
    "package_data": {},
    "classifiers": [
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Natural Language :: English",
        "Operating System :: MacOS",
        "Operating System :: Microsoft :: Windows",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 2.7",
        "Programming Language :: Python :: 3.4",
        "Programming Language :: Python :: 3.5",
        "Programming Language :: Python :: 3.6",
        "Programming Language :: Python :: 3.7",
        "Topic :: Software Development :: Libraries :: Application Frameworks"
    ]
}


# check platform
platform = sys.platform
ndkplatform = environ.get('NDKPLATFORM')
if ndkplatform is not None and environ.get('LIBLINK'):
    platform = 'android'
kivy_ios_root = environ.get('KIVYIOSROOT', None)
if kivy_ios_root is not None:
    platform = 'ios'

# check cython
skip_cython = False
if platform in ('ios', 'android'):
    print('\nCython check avoided.')
    skip_cython = True
else:
    try:
        from Cython.Distutils import build_ext
    except ImportError:
        print("\nCython is missing, it's required for compiling curly !\n\n")
        raise

# find libraries
if platform == "android":
    # XXX untested yet
    LIBRARIES = ["sdl", "curl", "sdl_image"]
    LIBRARY_DIRS = ["libs/" + getenv("ARCH")]
elif platform == "ios":
    raise Exception("TODO")
else:
    flags = pkgconfig("sdl2", "SDL2_image", "libcurl")
    INCLUDE_DIRS.extend(flags["include_dirs"])
    LIBRARIES.extend(flags["libraries"])


# create the extension
setup(
    cmdclass={'build_ext': build_ext},
    install_requires=INSTALL_REQUIRES,
    ext_modules=[
        Extension(
            "_curly", FILES,
            libraries=LIBRARIES,
            library_dirs=LIBRARY_DIRS,
            include_dirs=INCLUDE_DIRS,
            extra_link_args=EXTRA_LINK_ARGS
        )
    ],
    **SETUP_KWARGS
)
