# TODO: Tasks

All Tags:
#VisualEditor
#Simulation
#Assembler
#VM

## Fix the timestep
Tags: #Simulation

The simulation is subject to framerate instability currently, Ideally, Simulation time should be accumulated and then removed in fixed size steps to ensure simulation consistency.

--- 

## Upper Bound on Sim Elements
Tags: #Simulation

There should be either a hard upper bound placed on simulation elements, or some form of automatic detection of missing frame times to cap the simulation growth, this will stop the simulation from collapsing under load which is important for demoing the software.

---

## Allow other shapes for Sim Elements
Tags: #Simulation

Currently, the only supported shape is a 2 radii capsule, Other shapes would allow for more interesting variation in morphology.

---

## Push constants
Tags: #Editor

There needs to be a way to push different constant values for programs made with the visual editor. These incude:
- Numbers
- Colors
- Labels
- Booleans

--- 

## Parameter Get Set
Tags: #Editor, #VM

There needs to be a way to get and set parameters with the visual editor. This is a pre-made list of parameters of the simulation.

---

## Constant Folding
Tags: #Assembler

This is an extension of constants in the assembler that should support infix expression parsing of simple arithmetic equations. 

Ex: `3 + 4`, `SOME_CONSTANT * 2.4`, ...

At assemble time these constants should be folded into single values that can then be inserted into the VM_Program

---

## Constant UI
Tags: #Editor

The UI needs to be able to represent Nested constant expressions that can refer to other constants, This means that users need to be able to reference other constants somehow. This sounds hard to do with drag and drop due to the complex requirements.

---

## Editor Save/Load
Tags: #Editor

There needs to be a way to save and load programs in the editor. This should be text based and the load turns the cold text based representation to a hot Editor based representation.

---

## Add example programs
Tags: #Editor

There should be some default sample programs to show the capabilities of the system as well as how to use it.

---

## Editor write program
Tags: #Editor

There needs to be a funciton to take the current programs state and convert it to a text representation to be ingested by the assembler, or saved as a cold copy.

---

## Flush to assembler
Tags: #Editor, #Assembler, #Simulation

There must be a button to set the current program to the one in the editor. This should conver the program to text and pass it to a codepath in the sim that assembler the program and then loads it as the active program and restarts the simulation.

---

## Conditional Branching on Instructions
Tags: #Editor

There needs to be a way to make instructions conditional in the editor. Some conditional instructions take 2 inputs depending on the condition so there may need to be multiple input zones for these instrucitons.

---
