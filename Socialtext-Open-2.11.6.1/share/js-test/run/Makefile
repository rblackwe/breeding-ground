.PHONY: all clean

ALL_T_HTML:=$(shell ls -1 ../*.t.js | perl -pe 's/js$$/html/;s/^\.\.\///')

ALL_TARGETS:=$(ALL_T_HTML) index.html

all: $(ALL_TARGETS)

%.t.html:
	perl bin/render-template test.html $@

index.html: ../*.t.js
	perl bin/render-template index.html $@

clean:
	rm -fr $(ALL_TARGETS)

html:
	mkdir html
