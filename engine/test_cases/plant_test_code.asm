; Maybe we could compile each block to a seperate slice of instructions and then
; jumps could just swap the pointer?

; This is a constant, It will have a value that is calculated at compile time.
; It will be able to do constant folding as long as all inputs are constants.
let END_GROWTH_RATE = 123 * 0.0001
let TURN_ANGLE = TAU / 9
let BROWN = #D27D2DFF ; RGBA hex code
let PINK  = #FF00FFFF

; Unanswered Questions
; How are variables going to be handled. There is the VM stack but what if values need to live longer.
; How will cells be able to signal one another? I feel that this amy tie into the variable question.

; Here is how I am conceptualizing "blocks"
; Each block can hold N instructions, which are executed sequentially.
; Each block implicity returns at the end of it's scope.
; Blocks can contain sub-blocks for higher level constructs like loops or if
; Blocks can be referred to by their label which syntactically always begins with a ':'
; eg. to refer to block "Foo" use label :Foo
; If Foo had a sub-block "bar" then the corresponding label would be :Foo:bar
; If referring to "bar" from inside of "Foo" then the Label would not need to be
; fully qualified so :bar means :Foo:bar in this context
; Sub blocks do not interrupt the control flow of their parent blocks they can
; be inserted inbetween instructions but will have no effect unless jumped to.
Bud:
    get $Growth_Rate
    push END_GROWTH_RATE
    push 5.0
    mul
    ret/gt ; Conditional consumes both $growth_rate and the Calculated value

    rand
    push 0.33
    jump/gt :stem, :node_or_petal

    stem:
        push 0
        push :Bud
        spawn

        push :Stem
        set $State
    end

    node_or_petal:
        rand
        push 0.95
        push/lt :Node, :Petal
        set $State
    end
end

Node:
    rand
    push 0.88
    jump/gt :turn_right // This seems almost function like the only thing missing is parameter passing
    turn_right:
        push TURN_ANGLE
        push :Bud
        spawn
    end

    rand
    push 0.77
    jump/gt :turn_left
    turn_left:
        push -TURN_ANGLE ; Should this be ok?
        push :Bud
        spawn
    end

    push :Stem
    set $state
end

Stem:
    push BROWN
    set $Color
    ; Length += 0.001
    get $Lenght
    push 0.001
    add
    set $Length
    ; Thickness += 0.005
    get $Thickness
    push 0.005
    add
    set $Thickness
end

Petal:
    push PINK
    set $Color
end
