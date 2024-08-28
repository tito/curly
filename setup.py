import sys
from os import environ, getenv
from os.path import join, isdir
try:
    from setuptools import setup, Extension
except ImportError:
    from distutils.core import setup, Extension


def pkgconfig(*packages, **kw):
    flag_map = {'-I': 'include_dirs', '-L': 'library_dirs', '-l': 'libraries'}
    for name in flag_map.values():
        kw.setdefault(name, [])
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
        kw[flag].append(token[2:].decode('utf-8'))
    return kw


def getoutput(cmd, env=None):
    import subprocess
    p = subprocess.Popen(cmd,
                         shell=True,
                         stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE,
                         env=env)
    p.wait()
    if p.returncode:  # if not returncode == 0
        print('WARNING: A problem occurred while running {0} (code {1})\n'.
              format(cmd, p.returncode))
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
]

LIBRARIES = []
LIBRARY_DIRS = []
LIB_LOCATION = None
EXTRA_LINK_ARGS = []
INCLUDE_DIRS = []
INSTALL_REQUIRES = []
SETUP_KWARGS = {
    "name": "pycurly",
    "version": VERSION,
    "packages": ["curly"],
    "py_modules": ["setup"],
    "ext_package": "curly",
    "package_data": {},
    "classifiers": [
        "Development Status :: 4 - Beta", "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Natural Language :: English", "Operating System :: MacOS",
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
with_coverage = False
if platform in ('ios', 'android'):
    print('Cython check avoided.')
    with_cython = False
    from distutils.command.build_ext import build_ext
    FILES = ["curly/_curly.c"]
else:
    try:
        from Cython.Distutils import build_ext
        with_cython = True
        with_coverage = environ.get("WITH_COVERAGE")
    except ImportError:
        print("\nCython is missing, it's required for compiling curly !\n\n")
        raise

cython_directives = {}
define_macros = []
if with_coverage:
    cython_directives["binding"] = True
    cython_directives["embedsignature"] = True
    cython_directives["profile"] = True
    cython_directives["linetrace"] = True
    define_macros = [("CYTHON_PROFILE", 1), ("CYTHON_TRACE", 1),
                     ("CYTHON_TRACE_NOGIL", 1)]

# find libraries
if platform == "android":
    # XXX untested yet
    INCLUDE_DIRS = getenv("INCLUDE_DIRS").split(":")
    LIBRARIES = ["SDL2", "curl", "SDL2_image"]
    LIBRARY_DIRS = ["libs/" + getenv("ARCH")]
    # SDL2_image fix include directory not appearing
    for entry in INCLUDE_DIRS[:]:
        if "SDL2_image" in entry:
            INCLUDE_DIRS.append(entry + "/include")
elif platform == "ios":
    sysroot = environ.get("IOSSDKROOT", environ.get("SDKROOT"))
    if not sysroot:
        raise Exception("IOSSDKROOT is not set")
    INCLUDE_DIRS = [sysroot]
    LIBRARIES = []
    LIBRARY_DIRS = []
elif platform == "win32":
    INCLUDE_DIRS.append(join(getenv("CONDA_PREFIX"), "Lib", "include"))
    LIBRARY_DIRS.append(join(getenv("CONDA_PREFIX"), "Lib", "lib"))
    LIBRARIES = ["SDL2", "curl", "SDL2_image"]
else:
    flags = pkgconfig("sdl2", "SDL2_image", "libcurl")
    INCLUDE_DIRS.extend(flags["include_dirs"])
    LIBRARIES.extend(flags["libraries"])
    LIBRARY_DIRS.extend(flags["library_dirs"])

# create the extensions
extensions = [
    Extension("_curly",
              FILES,
              libraries=LIBRARIES,
              library_dirs=LIBRARY_DIRS,
              include_dirs=INCLUDE_DIRS,
              extra_link_args=EXTRA_LINK_ARGS,
              define_macros=define_macros)
]
if with_cython:
    from Cython.Build import cythonize
    extensions = cythonize(extensions, compiler_directives=cython_directives)

cmdclass = {'build_ext': build_ext}

# create the extension
setup(cmdclass=cmdclass,
      install_requires=INSTALL_REQUIRES,
      ext_modules=extensions,
      **SETUP_KWARGS)
