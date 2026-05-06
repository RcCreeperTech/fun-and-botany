export const willow = `
def ANGLE = 0.37
def GROW = 0.05
def RHISOME = #374F3CFF
def BARK1 = #614428FF
def BARK2 = #472D14FF
def LEAF1 = #20422DC2
def FLOWER1 = #AA00FF91
def FLOWER2 = #FF00E791

@(entrypoint, state)
def Node(cell):
    cell.interpolate_colors = true
    cell.color = RHISOME

    if cell.growth_rate >= GROW:
        return
    end

    if cell.depth > 6:
        if $Rand < 0.99:
            $Spawn(0, :Streamer)
            cell.state = :Vine
        end
    end

    turn = ANGLE if $Rand > 0.5 else -ANGLE
    if $Rand > 0.5:
        $Spawn(turn / 4, :Node)
        cell.state = :Trunk
    else:
        $Spawn(turn, :Fork)
        cell.state = :Trunk
    end
end

@state
def Fork(cell):
    if cell.growth_rate <= GROW:
        $Spawn(ANGLE, :Node)
        $Spawn(-ANGLE, :Node)
        cell.state = :Trunk
    end
end

@state
def Trunk(cell):

    if $Rand > 0.5:
        cell.state = :Trunk1
    else:
        cell.state = :Trunk2
    end
end

@state
def Trunk1(cell):
    cell.color = BARK1
end

@state
def Trunk2(cell):
    cell.color = BARK2
end

@state
def Vine(cell):
    cell.color = LEAF1
end

@state
def Flower(cell):
    cell.interpolate_colors = false
    cell.thickness = 0.1
    cell.length = 0
    cell.state = :Flower1 if $Rand > 0.5 else :Flower2
end

@state
def Flower1(cell):
    cell.color = FLOWER1
end

@state
def Flower2(cell):
    cell.color = FLOWER2
end

@state
def Streamer(cell):
    if cell.depth > 14:
        return
    end

    if cell.growth_rate >= GROW:
        return
    end

    cell.lignen = 0
    $Spawn(0, :Streamer)
    if $Rand > 0.33:
        $Spawn(0, :Flower)
    end
    cell.state = :Vine
end

  `;
export const candy = `
def ANGLE = 0.35
def GROW = 0.05
def CANDY_COLOR = #FF67E2FF

@(entrypoint, state)
def ping(cell):
    cell.color = #6672FFFF
    if cell.growth_rate < GROW:
        turn = 0
        if $Rand > .5:
            turn = ANGLE
        else:
            turn = -ANGLE
        end
        $Spawn(turn, :pong)
        cell.state = :white_candy
    end
end

@state
def pong(cell):
    if cell.growth_rate <= GROW:
        $Spawn(ANGLE, :ping)
        $Spawn(-ANGLE, :ping)
        cell.state = :red_candy
    end
end

@state
def white_candy(cell):
    cell.color = #FFFFFFFF
end

@state
def red_candy(cell):
    cell.color = CANDY_COLOR
end
  `;
export const palm = `
def ANGLE = 0.35
def GROW = 0.05
def TAU = 6.28

@(entrypoint, state)
def rhisome(cell):
    cell.color = #2B6B37FF
    if cell.growth_rate < GROW:
        if cell.depth > 8:
            cell.state = :fork
            return
        end

        r = $Rand
        if r > 0.5:
            $Spawn(0.05, :rhisome)
        else:
            $Spawn(-0.05, :rhisome)
        end
        cell.state = :Bark
    end
end

@state
def fork(cell):
    cell.color = #30663ADE
    cell.thickness = cell.thickness + 0.33
    cell.length = cell.length + 0.5
    if cell.growth_rate < GROW:
        $Spawn(-TAU / 4, :Bud)
        $Spawn(TAU / 4, :Bud)
        $Spawn(-TAU / 8, :Bud)
        $Spawn(TAU / 8, :Bud)
        cell.state = :Bark
    end
end

@state
def Bud(cell):
    cell.lignen = 0.65
    if cell.depth > 15:
        cell.state = :Stem
    end

    if cell.growth_rate < GROW:
        $Spawn(0.35, :Leaf)
        $Spawn(0, :Leaf)
        $Spawn(-0.35, :Leaf)
        $Spawn(0, :Bud)
        cell.state = :Stem // FIXME: this silently failed with :stem
    end
end

@state
def Stem(cell):

end

@state
def Leaf(cell):
    cell.interpolate_colors = true
    cell.color = #EB20DE8F
    cell.lignen = 0.13
    cell.length = cell.length + 0.8
end

@state
def Bark(cell):
    cell.color = #664624FF
end
  `;

export const steven = `
def ANGLE = 0.37
def GROW = 0.05
def RHISOME = #276E37FF
def BARK1 = #9C6E43FF
def BARK2 = #85582FFF
def LEAF1 = #06D65696
def LEAF2 = #14B07496

@(entrypoint, state)
def Node(cell):
    cell.interpolate_colors = true
    cell.color = RHISOME

    if cell.growth_rate >= GROW:
        return
    end

    if cell.depth > 6:
        if $Rand < 0.99:
            $Spawn(0, :Foliage)
            cell.state = :Trunk
        end
    end

    turn = ANGLE if $Rand > 0.5 else -ANGLE
    $Spawn(turn, :Fork)
    cell.state = :Trunk
end

@state
def Fork(cell):
    if cell.growth_rate <= GROW:
        $Spawn(ANGLE, :Node)
        $Spawn(-ANGLE, :Node)
        cell.state = :Trunk
    end
end

@state
def Trunk(cell):

    if $Rand > 0.5:
        cell.state = :Trunk1
    else:
        cell.state = :Trunk2
    end
end

@state
def Trunk1(cell):
    cell.color = BARK1
end

@state
def Trunk2(cell):
    cell.color = BARK2
end

@(state, terminal)
def Foliage(cell):
    cell.lignen = 0
    cell.length = 0
    cell.thickness = cell.thickness + 0.25
    cell.state = :Leaf1 if $Rand > 0.5 else :Leaf2
end

@state
def Leaf1(cell):
    cell.color = LEAF1
    cell.thickness = cell.thickness + 0.25
end

@state
def Leaf2(cell):
    cell.color = LEAF2
    cell.thickness = cell.thickness + 0.25
end
`;

export const twister = `
def ANGLE = 0.57
def DIMINISH = 0.055
def GROW = 0.15
def RHISOME = #FFB300FF
def BARK1 = #B80088FF
def BARK2 = #7300A1FF
def BARK3 = #008CE8FF

@(entrypoint, state)
def Node(cell):
    cell.interpolate_colors = true
    cell.color = RHISOME

    if cell.growth_rate >= GROW:
        return
    end

    if cell.depth < 4:
        $Spawn(ANGLE/5, :Lefty)
        cell.state = :Done
        cell.color = BARK3
        return
    end

    if $Rand < 0.95:
        $Spawn(ANGLE/5, :Lefty)
    end

    $Spawn(-ANGLE, :Righty)
    cell.state = :Done
    cell.color = BARK3
end

@state
def Lefty(cell):
    if cell.growth_rate >= GROW:
        return
    end
    $Spawn(0, :Node)
    cell.state = :Done
    cell.color = BARK3
end

@state
def Righty(cell):
    if cell.growth_rate >= GROW:
        return
    end

    if $Rand < 0.2:
        $Spawn(ANGLE/5, :Lefty)
    end

    off = DIMINISH * cell.depth
    $Spawn(-ANGLE - off, :RightyAlt)
    cell.state = :Done
    cell.color = BARK1
end

@state
def RightyAlt(cell):
    if cell.growth_rate >= GROW:
        return
    end

    off = DIMINISH * cell.depth
    $Spawn(-ANGLE - off, :Righty)
    cell.state = :Done
    cell.color = BARK2
end

@state
def Done(cell):

end
`;
