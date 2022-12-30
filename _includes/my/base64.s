; A base64 decoder, written in 8086 assembly language.
; Assemble using the Flat Assembler (https://flatassembler.net/)

; Emit a raw binary file, and arrange for labels to start at 0
            format  binary
            org     0

; Entry point
; BIOS loads us at 0x7C00, but we don't know the exact segment/offset combo:
; it could be 07C0:0000, 0000:7C00 or any other equivalent form.
; So the program lives at [0x7C00, 0x7DFF].
start:

; Place the stack at [0x7E00, 0x7FFF) and enable interrupts
            cli
            cld
            mov     ax, 07E0h
            mov     ss, ax
            mov     sp, 0200h
            sti

; Jump to the label below while normalizing the segment/offset pair
; so that effective addresses are correct w.r.t. "org"
            mov     ax, 07C0h
            mov     ds, ax     ; init data segments
            mov     es, ax     ; ...
            push    ax
            mov     ax, @f
            push    ax
            retf
            
@@:
            mov     si, msg

; "chunk" processes 4 bytes of base64 data, yielding 3 characters            
chunk:
            ; End of string?
            cmp     byte [si], 0
            je      endloop
            xor     bx, bx
            mov     cx, 4
            mov     di, c1
            ; Initially mark c3 and c4 as padded
            mov     word [c3], 0FFFFh
            
b64Char:
            lodsb
            ; If we read a =, the chunk is padded and there
            ; are no more bits to read.
            cmp     al, '='
            je      printer
            mov     bl, al
            mov     al, [bx + base64]
            stosb

            loop    b64Char
            
; As soon as we get here, we have read 4 b64 characters and
; placed them into c1, c2, c3, c4. Only the least significant
; 6 bits for each cX are used. But for c3 and c4, if the MSB
; is set it means there is no character because the block was
; padded.
; Visually: O = clear bit, I = set bit
;           1/2/3 = bit belongs to decoded char 1/2/3
; c1 = OO111111
; c2 = OO112222
; c3 = OO222233 | IIIIIIII (padding)
; c4 = OO333333 | IIIIIIII (padding)
printer:
            ; Reassemble decoded character 1 from c1 and c2
            mov     cx, 2
            mov     ax, word [c1]       ; also read c2
            xchg    al, ah
            shl     al, cl
            mov     cl, 6
            shr     ax, cl
            call    print_char
            
            ; Reassemble decoded character 2 from c2 and c3,
            ; but only if we have a c3
            test    byte [c3], 80h
            jnz     endloop
            
            mov     cl, 4
            mov     al, [c2]
            shl     al, cl
            mov     ah, [c3]
            shr     cl, 1
            shr     ah, cl
            or      al, ah
            call    print_char
            
            ; Reassemble decoded character 3 from c3 and c4,
            ; but only if we have a c4
            test    byte [c4], 80h
            jnz     endloop
            
            mov     ax, word [c3]       ; also read c4
            xchg    al, ah
            shl     al, cl
            shr     ax, cl
            call    print_char
            
            jmp     chunk
            
endloop:
            hlt
            jmp     endloop
            
; Put print boilerplate in a procedure
; It expects the characters in AL and trashes AH, BH
print_char:
            push    cx
            xor     bh, bh
            xor     cx, cx
            mov     ah, 0Eh
            int     10h
            pop     cx
            retn

; Message to decode
msg         db      "SGFwcHkgaG9saWRheXMhISE=", 0

; Table converting ASCII characters to their base64 group of 6 bits.
; It starts at the lowest used character (+), that's why we use "virtual"
; to adjust the offest below.
chartab     db      62                                                  ; +
            rb      3
            db      63                                                  ; /
            db      52, 53, 54, 55, 56, 57, 58, 59, 60, 61              ; 0-9
            rb      7
            db      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12   ; A-Z
            db      13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25  ; ...
            rb      6
            db      26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38  ; a-z
            db      39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51  ; ...

; The first used char is + (43)
            virtual at chartab - '+'
base64      db      ?
            end     virtual

; Base64 bytes under examination
; Must be word-aligned, because we read them as words in some cases
            align   2
c1          db      ?
c2          db      ?
c3          db      ?
c4          db      ?

; Pad the program to 510 bytes, and append the MBR signature at the end.
; This makes it a proper MBR that can be executed by BIOS.
            rb      510 - $
            db      055h
            db      0AAh
