#ifndef _MODEL_TEST_H
#define _MODEL_TEST_H
#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits; \
        .align 8; .global tohost; tohost: .dword 0; \
        .align 8; .global fromhost; fromhost: .dword 0; \
        .popsection; \
        .align 8; .global begin_regstate; begin_regstate: .word 128; \
        .align 8; .global end_regstate; end_regstate: .word 4;
#define RVMODEL_BOOT
#define RVMODEL_HALT \
        la t0, tohost; li t1, 1; sw t1, 0(t0); \
        .global cve2_act_halt; cve2_act_halt: \
        self_loop: j self_loop;
#define RVMODEL_DATA_BEGIN \
        RVMODEL_DATA_SECTION \
        .align 4; .global begin_signature; begin_signature:
#define RVMODEL_DATA_END .align 4; .global end_signature; end_signature:
#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT
#endif
