from setuptools import setup
from Cython.Build import cythonize
from Cython.Compiler import Options


Options.embed = 'main'


setup(
    ext_modules = cythonize(
        ["*.pyx"], compiler_directives={'language_level' : "3"}
    )
)
