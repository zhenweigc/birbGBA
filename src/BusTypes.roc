BusTypes :: {}.{
	Width : [W8, W16, W32]
	HalfOrWord : [W16, W32]
	Direction : [Read, Write]

	to_bus_width : HalfOrWord -> Width # All these just to calm down the compiler
	to_bus_width = |w| w
}
