SECTIONS {
  . = CAVE_VA;
  .cave : SUBALIGN(1) {
    shim32.o(.text)
    *(.text .text.*)
    . = ALIGN(16);
    *(.rdata .rdata.* .rodata .rodata.*)
  }
  /DISCARD/ : { *(.pdata) *(.xdata) *(.bss) *(.data) *(.comment) *(.note.*) *(.eh_frame) }
}
