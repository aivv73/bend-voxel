# Destructible Voxel World

Glossary for the proposed game engine model. The world consists of material that can be destroyed and separated into moving parts.

## Language

**Voxel**:
The smallest material cell in the local grid of the world or an individual body. An empty cell represents the absence of material.
_Avoid_: Minecraft block, physical body.

**Material**:
A substance with visual and physical properties, such as stone, wood, or metal.

**Static world**:
The stationary part of the environment connected to the level's anchors.

**Anchor**:
A region that the level rules define as fixed. Material connected to an anchor remains part of the static world.

**Voxel body**:
A connected piece of material with its own local grid and position in space. The body can move and rotate as a whole.

**Fragment**:
A voxel body detached by destruction of the world or another body.
_Avoid_: particle, chunk.

**Destruction**:
A change to material that can remove voxels and sever connections between the remaining parts.

**Damage**:
Accumulated impact on material before its removal. Destruction without accumulated damage is also allowed.

**Particle**:
A visual dust or small debris effect that is not part of the solid world.
_Avoid_: fragment.
