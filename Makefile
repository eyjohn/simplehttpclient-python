default: all

all: build_ext

build_ext: simplehttpclient/ext.cpython-38.so

simplehttpclient/ext.cpython-38.so: simplehttpclient/ext.pyx setup.py
	python setup.py build_ext --inplace

clean:
	rm simplehttpclient/*.so simplehttpclient/*.o
