import Bits

Mode : [GP, JOY_BUS, EightBit, ThirtyTwoBit, SixteenBit, UART]

SerialRegs :: {
    rcnt : U16,
    siocnt : U16   
}.{
    init : () -> SerialRegs
    init = || {
        {
            rcnt : 0,
            siocnt : 0  
        }
    }

    mode_decode : U16, U16 -> Mode
    mode_decode = |rcnt, siocnt| {
        # P126 of Nintendo GBA manual
        if Bits.get_seg_of_u16_certain(rcnt, 14, 2) == 2 {
            GP
        }else if Bits.get_seg_of_u16_certain(rcnt, 14, 2) == 3 {
            JOY_BUS
        } else if Bits.get_seg_of_u16_certain(siocnt, 12, 2) == 0 {
            EightBit
        } else if Bits.get_seg_of_u16_certain(siocnt, 12, 2) == 1{
            ThirtyTwoBit
        } else if Bits.get_seg_of_u16_certain(siocnt, 12, 2) == 2 {
            SixteenBit
        } else {
            UART
        }
    }
}