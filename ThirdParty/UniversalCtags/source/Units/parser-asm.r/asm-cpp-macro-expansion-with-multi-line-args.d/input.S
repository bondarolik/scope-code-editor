#define ENTRY(SYMBOL,LABEL) .global SYMBOL	;\
LABEL: \
	nop

ENTRY(A, B)
ENTRY(C,
	D)
