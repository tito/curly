.PHONY = all build_ext clean

all: build_ext

build_ext:
		python setup.py build_ext --inplace

clean:
		rm -rf curly/*.so curly/_curly.c

tests:
		pytest -v

coverage: clean
		WITH_COVERAGE=1 python setup.py build_ext --inplace -f
		coverage run --source curly setup.py test
		coverage report -m
