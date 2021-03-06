PYCMD=python setup.py
GH_PAGES_SOURCES=bayesian_quadrature docs VERSION.txt README.md Makefile setup.py

all:
	$(PYCMD) bdist

source:
	$(PYCMD) sdist

upload:
	$(PYCMD) sdist upload

install:
	$(PYCMD) install

clean:
	$(PYCMD) clean --all
	make -C docs clean
	make -C docs/ipynb clean
	rm -rf dist
	rm -f MANIFEST
	rm -f README
	rm -f *.pyc
	rm -f bayesian_quadrature/ext/*.c
	rm -f bayesian_quadrature/ext/*.so
	rm -rf *.egg-info
	rm -f .coverage
	rm -rf htmlcov
	rm -rf docs/_build

cython:
	$(PYCMD) build_ext --inplace

test:
	py.test --cov bayesian_quadrature

gh-pages:
	make clean || true
	git checkout gh-pages
	rm -rf _sources _static _modules _images
	git checkout master $(GH_PAGES_SOURCES)
	git reset HEAD
	pandoc --from markdown --to rst -o README.rst README.md
	make -C docs/ipynb all
	python setup.py build_ext --inplace
	make -C docs html
	mv -fv docs/_build/html/* .
	rm -rf $(GH_PAGES_SOURCES) README.rst build
	git add -A
	git ci -m "Generated gh-pages for `git log master -1 --pretty=short --abbrev-commit`" && git push origin gh-pages
	git checkout master

sphinx:
	make -C docs/ipynb all
	python setup.py build_ext --inplace
	make -C docs html
