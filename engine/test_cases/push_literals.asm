; This is a test of pushing literal values.
; I like writing comments

Main:
	push .1
	push 1_2_3_4
	push -1_2_3_4

	push 0.1
	; Pointless comment
	push -.12
	push 1
	; Pointless comment 2


	push 0
	push true
	push false
	push #181818ff ; Random Comment
	push #281858fF
end
