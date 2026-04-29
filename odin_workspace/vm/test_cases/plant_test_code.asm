const END_GROWTH_RATE = 0.05
const RIGHT_TURN_ANGLE = 0.69813 ; TAU / 9
const LEFT_TURN_ANGLE = -0.69813 ; -TAU / 9 TODO: Unary minus for constant expressions

Colors:
    const BROWN = #D27F2DF0
    const PINK  = #FF00FFFF
end

Main:
    push END_GROWTH_RATE
    get $Growth_Rate
    ret/gt ; Conditional consumes both $growth_rate and the Calculated value

    rand
    push 0.33
    jump/gt :stem, :node_or_petal

    stem:
        push 0 ; Angle
        push :Main ; Start State
        spawn

        push :Stem
        set $State
    end

    node_or_petal:
        push 0.95
        rand
        push/lt :Node, :Petal
        set $State
    end
end

Node:
    rand
    push 0.88
    call/gt :turn_right
    turn_right:
        push RIGHT_TURN_ANGLE
        push :Main
        spawn
    end

    rand
    push 0.77
    call/gt :turn_left
    turn_left:
        push LEFT_TURN_ANGLE ; Should this be ok?
        push :Main
        spawn
    end

    push :Stem
    set $State
end

Stem:
    push Colors.BROWN
    set $Color
    ; Length += 0.001
    get $Length
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
    push Colors.PINK
    set $Color
end
