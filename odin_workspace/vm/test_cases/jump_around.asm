; Testing for the jump instruction
Main:

    push 1
    push 0

    jump/eq :End, :Fail

    Inner:
        jump :End
    end

end

Fail:
    push 123
    jump :Main:Inner
end

End:
    push 67
end
