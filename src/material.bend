import Base

# Stable voxel material IDs. The Vulkan palette uses the same IDs; body
# detachment changes presentation, never the material stored in a voxel.
def foundation() -> U32: 1
def concrete() -> U32: 2
def frame() -> U32: 3
def machinery() -> U32: 4

# Foundation cells are the current level's protected anchors.
def is_anchor(material: U32) -> Bool:
  U32.is_eq(material,foundation())
