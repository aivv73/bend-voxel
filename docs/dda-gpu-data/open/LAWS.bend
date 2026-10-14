import Base
import ../candidate-dda.bend as X
import ../../../render.bend as R

law dda_assignment_bound_open:
	for +schedule: X.Schedule
	for +address: X.Address
	for bounded: {X.Address.bounded(schedule,address) == True{} : Bool}
	{X.Point.bounded(X.Assign.pixel(schedule,address)) == True{} : Bool}

law dda_inverse_bound_open:
	for +schedule: X.Schedule
	for +point: X.Point
	for bounded: {X.Point.bounded(point) == True{} : Bool}
	{X.Address.bounded(schedule,X.Assign.inverse(schedule,point)) == True{} : Bool}

law dda_assignment_left_inverse_open:
	for +schedule: X.Schedule
	for +address: X.Address
	for bounded: {X.Address.bounded(schedule,address) == True{} : Bool}
	{X.Assign.inverse(schedule,X.Assign.pixel(schedule,address)) == address : X.Address}

law dda_assignment_right_inverse_open:
	for +schedule: X.Schedule
	for +point: X.Point
	for bounded: {X.Point.bounded(point) == True{} : Bool}
	{X.Assign.pixel(schedule,X.Assign.inverse(schedule,point)) == point : X.Point}

law dda_assignment_complete_coverage_open:
	for +schedule: X.Schedule
	for +point: X.Point
	for bounded: {X.Point.bounded(point) == True{} : Bool}
	exs address: X.Address
	{X.Address.bounded(schedule,address) == True{} : Bool} &
	{X.Assign.pixel(schedule,address) == point : X.Point}

law dda_assignment_unique_ownership_open:
	for +schedule: X.Schedule
	for +a: X.Address
	for +b: X.Address
	for a_bounded: {X.Address.bounded(schedule,a) == True{} : Bool}
	for b_bounded: {X.Address.bounded(schedule,b) == True{} : Bool}
	for same: {X.Assign.pixel(schedule,a) == X.Assign.pixel(schedule,b) : X.Point}
	{a == b : X.Address}

law dda_selected_pixel_placement_open:
	for +schedule: X.Schedule
	for +skip: Bool
	for +grid: X.Grid
	for +basis: R.Basis
	for +palette: X.Palette
	for +ground: R.GroundLighting
	for +point: X.Point
	for bounded: {X.Point.bounded(point) == True{} : Bool}
	{X.Native.at(9n,X.Frame.selected(schedule,skip,grid,basis,palette,ground),point) == X.Frame.seq(0n,skip,grid,basis,palette,ground,X.Point.x(point),X.Point.y(point),1) : Image}

law dda_selected_frame_complete_open:
	for schedule: X.Schedule
	for skip: Bool
	for grid: X.Grid
	for basis: R.Basis
	for palette: X.Palette
	for ground: R.GroundLighting
	{X.Native.full(9n,X.Frame.selected(schedule,skip,grid,basis,palette,ground)) == True{} : Bool}
