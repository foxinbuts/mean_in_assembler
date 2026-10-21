NASM = nasm
NASMFLAGS = -f elf64 -g -F dwarf
LD = ld
LDFLAGS =

TARGET = average
SRCS = main.asm
OBJS = main.o

FILE ?= data.txt

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

%.o: %.asm
	$(NASM) $(NASMFLAGS) -o $@ $<

run: $(TARGET)
	@if [ -f "$(FILE)" ]; then \
		./$(TARGET) $(FILE); \
	elif [ -f "../$(FILE)" ]; then \
		./$(TARGET) ../$(FILE); \
	else \
		./$(TARGET) $(FILE); \
	fi

clean:
	rm -f $(TARGET) $(OBJS)

.PHONY: all run clean
