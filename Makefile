snake: snake.asm
	nasm -f elf64 -F dwarf -g ./snake.asm -o snake.o
	clang -mno-omit-leaf-frame-pointer -fno-omit-frame-pointer -m64 ./snake.o -o snake
