class_name Layers
## Physics layer bits. Sight and bullets both test WORLD | HOSTILE (or WORLD | PLAYER),
## so anything on WORLD (walls, closed doors, pillars, containers) blocks both.

const WORLD := 1
const PLAYER := 2
const HOSTILE := 4
const PICKUP := 8
