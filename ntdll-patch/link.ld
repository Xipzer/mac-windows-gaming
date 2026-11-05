SECTIONS {
  . = CAVE_VA;
  .cave : {
    shim.o(.text)
    *(.text .text.*)
    . = ALIGN(16);
    *(.rdata .rdata.* .rodata .rodata.*)
  }
  /DISCARD/ : { *(.pdata) *(.xdata) *(.bss) *(.data) *(.comment) *(.note.*) }
}
