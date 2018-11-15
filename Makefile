.PHONY = all build_ext clean

all: build_ext

build_ext:
		python setup.py build_ext --inplace

clean:
		rm curly/*.so
