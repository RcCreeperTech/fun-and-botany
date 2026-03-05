; This is a test of all the basic operations of the form <op>(/<cond>)?
;

Main:
    push 1
    push 2

    pop

    push 0
    push 0
    pop/eq

    push 1
    push 2

    add

    push 3

    push 0
    push 0
    add/eq ; HEAD=6

    push 6

    sub ; HEAD=0

    push 0

    rand/eq ; Will push a random value because 0=0
    pop ; Hard to test with non-deterministic values

    push 3
    push 4

    push 1000
    push 0.5
    mul

    push 1000

    mul/gt ; HEAD=12

    push 3
    div ; HEAD=4

end
