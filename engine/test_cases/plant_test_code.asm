const END_GROWTH_RATE = 0.05
const TURN_ANGLE = 0.69813 ; TAU / 9

Colors:
    const BROWN = #D27D2DFF ; RGBA hex code
    const PINK  = #FF00FFFF
end

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
    jump/gt :turn_right ; This seems almost function like the only thing missing is parameter passing
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
