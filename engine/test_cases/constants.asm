const FOO = 123
const PI = 3.14159

Main:
    push FOO ; 1337
    push PI ; 3.14159
    push Colors.RED ; #ff0000ff
    push Inner.Dinner.PI ; 4
    const FOO = 1337

    Inner:
        Dinner:
            push FOO ; 1337
            push Colors.RED ; #ff0000ff

            push true
            push true
            push/eq Colors.RED, Colors.GREEN ; #00ff00ff

            const PI = 4
            push PI ; 4
        end
    end
end

Other:
    const FOO = 456
    Inner:
        push FOO ; 456
    end
end

Colors:
    const RED = #ff0000ff
    const GREEN = #00ff00ff
    push Main.Inner.Dinner.PI ; 4
end
