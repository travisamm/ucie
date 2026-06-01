`timescale 1ns/1ps
/*
Run MBINIT:
make mbinit                                  # default: test_mbinit_sanity
make mbinit MBTEST=test_mbinit_sanity
make mbinit MBTEST=test_mbinit_param_mismatch
make mbinit MBTEST=test_mbinit_param_only
make mbinit MBTEST=test_mbinit_cal
make mbinit MBTEST=test_mbinit_repairclk
make mbinit_all                              # all MBINIT UVM tests (same list as mbinit_regress); logs in run_logs/mbinit
make mbinit_regress                          # alias for mbinit_all
Optional REPAIRMB requester trace (FIRRTL names; only while currentState==REPAIRMB):
  make mbinit MBINIT_XRUN_EXTRA='+define+MBINIT_RM05_DEBUG' MBTEST=test_mbinit_rm05_post_repair_persist

Run MBTRAIN:
make mbtrain                                 # default: mbtrain_base_test
make mbtrain MBTRAINTEST=mbtrain_base_test
make mbtrain_regress                       # runs mbtrain_base_test and mbtrain_timeout_test
*/
module mbinit_tb_top;
  import uvm_pkg::*;
  import mbinit_env_pkg::*;
  import mbinit_seq_pkg::*;
  import mbinit_test_pkg::*;

  logic clock;
  logic reset;
  logic por_reset;

  initial begin clock = 0; forever #5 clock = ~clock; end
  // Pass 6: reset generation is power-on reset OR a sequence-injected reset. The
  // reset agent drives rst_if.reset_req; the combined DUT reset (assign below) is
  // the OR of the two, so mid-sim resets can be injected WITHOUT touching the DUT
  // port connection (.reset(reset) is unchanged). Mirrors SBINIT's logphy_tb_top.
  initial begin por_reset = 1; #20 por_reset = 0; end

  mbinit_if vif(clock, reset);

  // -------------------------------------------------------------------------
  // Pass 2: split interfaces (clocking blocks + drv/mon modports). Staged as
  // PASSIVE OBSERVATION MIRRORS of the monolithic mbinit_if - the DUT still
  // binds to vif below, untouched, so every existing test stays green. The
  // mirror assigns (one direction only: split <= vif) live after the DUT
  // instantiation. The DUT-port migration + bridge flip happens in Pass 3.
  // -------------------------------------------------------------------------
  mb_ctrl_if           ctrl_if      (clock, reset);
  mb_req_if            req_if       (clock, reset);
  mb_rsp_if            rsp_if       (clock, reset);
  mb_reset_if          rst_if       (clock, reset);
  mb_cal_if            cal_if       (clock, reset);
  mb_pattern_writer_if pw_if        (clock, reset);
  mb_pattern_reader_if pr_if        (clock, reset);
  mb_pttest_req_if     pttest_req_if(clock, reset);
  mb_pttest_rsp_if     pttest_rsp_if(clock, reset);
  mb_lane_ctrl_if      lane_ctrl_if (clock, reset);

  // Pass 6: combined DUT reset = POR | sequence-injected reset_req. rst_if is
  // observed by the reset monitor and driven (reset_req) by mbinit_reset_driver.
  assign reset = por_reset | rst_if.reset_req;


  MBInitSM dut (
    .clock  (clock),
    .reset  (reset),

    // FSM control
    .io_fsmCtrl_start                (vif.fsmCtrl_start),
    .io_fsmCtrl_substateTransitioning(vif.fsmCtrl_substateTransitioning),
    .io_fsmCtrl_error                (vif.fsmCtrl_error),
    .io_fsmCtrl_done                 (vif.fsmCtrl_done),

    // Local PHY settings
    .io_localPhySettings_valid                 (vif.localPhySettings_valid),
    .io_localPhySettings_bits_voltageSwing     (vif.localPhySettings_voltageSwing),
    .io_localPhySettings_bits_maxDataRate      (vif.localPhySettings_maxDataRate),
    .io_localPhySettings_bits_clockMode        (vif.localPhySettings_clockMode),
    .io_localPhySettings_bits_clockPhase       (vif.localPhySettings_clockPhase),
    .io_localPhySettings_bits_ucieSx8         (vif.localPhySettings_ucieSx8),
    .io_localPhySettings_bits_sbFeatExt       (vif.localPhySettings_sbFeatExt),
    .io_localPhySettings_bits_txAdjRuntime    (vif.localPhySettings_txAdjRuntime),
    .io_localPhySettings_bits_moduleId         (vif.localPhySettings_moduleId),

    // Negotiated PHY settings (DUT outputs → interface for observation)
    .io_negotiatedPhySettings_valid                (vif.negotiatedPhySettings_valid),
    .io_negotiatedPhySettings_bits_voltageSwing    (vif.negotiatedPhySettings_voltageSwing),
    .io_negotiatedPhySettings_bits_maxDataRate     (vif.negotiatedPhySettings_maxDataRate),
    .io_negotiatedPhySettings_bits_clockMode       (vif.negotiatedPhySettings_clockMode),
    .io_negotiatedPhySettings_bits_clockPhase      (vif.negotiatedPhySettings_clockPhase),
    .io_negotiatedPhySettings_bits_ucieSx8        (),
    .io_negotiatedPhySettings_bits_sbFeatExt      (),
    .io_negotiatedPhySettings_bits_txAdjRuntime   (),
    .io_negotiatedPhySettings_bits_moduleId        (vif.negotiatedPhySettings_moduleId),

    // State outputs (io_interoperableParamsNotFound is internal; see mbinit_bind_exports.sv)
    .io_currentState                (vif.currentState),
    .io_usingPatternWriter          (vif.usingPatternWriter),
    .io_usingPatternReader          (vif.usingPatternReader),
    .io_applyLaneReversal           (vif.applyLaneReversal),
    .io_localFunctionalLanes        (vif.localFunctionalLanes),
    .io_txWidthChanged              (vif.txWidthChanged),
    .io_remoteFunctionalLanes       (vif.remoteFunctionalLanes),
    .io_rxWidthChanged              (vif.rxWidthChanged),

    // mbLaneCtrlIo — En polarity: 1=enabled, 0=disabled
    .io_mbLaneCtrlIo_txDataEn_0  (vif.mbLaneCtrl_txDataEn[0]),
    .io_mbLaneCtrlIo_txDataEn_1  (vif.mbLaneCtrl_txDataEn[1]),
    .io_mbLaneCtrlIo_txDataEn_2  (vif.mbLaneCtrl_txDataEn[2]),
    .io_mbLaneCtrlIo_txDataEn_3  (vif.mbLaneCtrl_txDataEn[3]),
    .io_mbLaneCtrlIo_txDataEn_4  (vif.mbLaneCtrl_txDataEn[4]),
    .io_mbLaneCtrlIo_txDataEn_5  (vif.mbLaneCtrl_txDataEn[5]),
    .io_mbLaneCtrlIo_txDataEn_6  (vif.mbLaneCtrl_txDataEn[6]),
    .io_mbLaneCtrlIo_txDataEn_7  (vif.mbLaneCtrl_txDataEn[7]),
    .io_mbLaneCtrlIo_txDataEn_8  (vif.mbLaneCtrl_txDataEn[8]),
    .io_mbLaneCtrlIo_txDataEn_9  (vif.mbLaneCtrl_txDataEn[9]),
    .io_mbLaneCtrlIo_txDataEn_10 (vif.mbLaneCtrl_txDataEn[10]),
    .io_mbLaneCtrlIo_txDataEn_11 (vif.mbLaneCtrl_txDataEn[11]),
    .io_mbLaneCtrlIo_txDataEn_12 (vif.mbLaneCtrl_txDataEn[12]),
    .io_mbLaneCtrlIo_txDataEn_13 (vif.mbLaneCtrl_txDataEn[13]),
    .io_mbLaneCtrlIo_txDataEn_14 (vif.mbLaneCtrl_txDataEn[14]),
    .io_mbLaneCtrlIo_txDataEn_15 (vif.mbLaneCtrl_txDataEn[15]),
    .io_mbLaneCtrlIo_txClkEn     (vif.mbLaneCtrl_txClkEn),
    .io_mbLaneCtrlIo_txValidEn   (vif.mbLaneCtrl_txValidEn),
    .io_mbLaneCtrlIo_txTrackEn   (vif.mbLaneCtrl_txTrackEn),
    .io_mbLaneCtrlIo_rxDataEn_0  (vif.mbLaneCtrl_rxDataEn[0]),
    .io_mbLaneCtrlIo_rxDataEn_1  (vif.mbLaneCtrl_rxDataEn[1]),
    .io_mbLaneCtrlIo_rxDataEn_2  (vif.mbLaneCtrl_rxDataEn[2]),
    .io_mbLaneCtrlIo_rxDataEn_3  (vif.mbLaneCtrl_rxDataEn[3]),
    .io_mbLaneCtrlIo_rxDataEn_4  (vif.mbLaneCtrl_rxDataEn[4]),
    .io_mbLaneCtrlIo_rxDataEn_5  (vif.mbLaneCtrl_rxDataEn[5]),
    .io_mbLaneCtrlIo_rxDataEn_6  (vif.mbLaneCtrl_rxDataEn[6]),
    .io_mbLaneCtrlIo_rxDataEn_7  (vif.mbLaneCtrl_rxDataEn[7]),
    .io_mbLaneCtrlIo_rxDataEn_8  (vif.mbLaneCtrl_rxDataEn[8]),
    .io_mbLaneCtrlIo_rxDataEn_9  (vif.mbLaneCtrl_rxDataEn[9]),
    .io_mbLaneCtrlIo_rxDataEn_10 (vif.mbLaneCtrl_rxDataEn[10]),
    .io_mbLaneCtrlIo_rxDataEn_11 (vif.mbLaneCtrl_rxDataEn[11]),
    .io_mbLaneCtrlIo_rxDataEn_12 (vif.mbLaneCtrl_rxDataEn[12]),
    .io_mbLaneCtrlIo_rxDataEn_13 (vif.mbLaneCtrl_rxDataEn[13]),
    .io_mbLaneCtrlIo_rxDataEn_14 (vif.mbLaneCtrl_rxDataEn[14]),
    .io_mbLaneCtrlIo_rxDataEn_15 (vif.mbLaneCtrl_rxDataEn[15]),
    .io_mbLaneCtrlIo_rxClkEn     (vif.mbLaneCtrl_rxClkEn),
    .io_mbLaneCtrlIo_rxValidEn   (vif.mbLaneCtrl_rxValidEn),
    .io_mbLaneCtrlIo_rxTrackEn   (vif.mbLaneCtrl_rxTrackEn),

    // Cal
    .io_mbInitCalDone  (vif.mbInitCalDone),
    .io_mbInitCalStart (vif.mbInitCalStart),

    // Requester SB lane
    .io_requesterSbLaneIo_tx_ready     (vif.requesterSbLaneIo_tx_ready),
    .io_requesterSbLaneIo_tx_valid     (vif.requesterSbLaneIo_tx_valid),
    .io_requesterSbLaneIo_tx_bits_data (vif.requesterSbLaneIo_tx_bits_data),
    .io_requesterSbLaneIo_rx_ready     (vif.requesterSbLaneIo_rx_ready),
    .io_requesterSbLaneIo_rx_valid     (vif.requesterSbLaneIo_rx_valid),
    .io_requesterSbLaneIo_rx_bits_data (vif.requesterSbLaneIo_rx_bits_data),

    // Responder SB lane
    .io_responderSbLaneIo_tx_ready     (vif.responderSbLaneIo_tx_ready),
    .io_responderSbLaneIo_tx_valid     (vif.responderSbLaneIo_tx_valid),
    .io_responderSbLaneIo_tx_bits_data (vif.responderSbLaneIo_tx_bits_data),
    .io_responderSbLaneIo_rx_ready     (vif.responderSbLaneIo_rx_ready),
    .io_responderSbLaneIo_rx_valid     (vif.responderSbLaneIo_rx_valid),
    .io_responderSbLaneIo_rx_bits_data (vif.responderSbLaneIo_rx_bits_data),

    // PatternWriter
    .io_patternWriterIo_req_ready            (vif.patternWriterIo_req_ready),
    .io_patternWriterIo_req_valid            (vif.patternWriterIo_req_valid),
    .io_patternWriterIo_req_bits_patternType (vif.patternWriterIo_req_bits_patternType),
    .io_patternWriterIo_resp_complete        (vif.patternWriterIo_resp_complete),

    // PatternReader
    .io_patternReaderIo_req_ready                   (vif.patternReaderIo_req_ready),
    .io_patternReaderIo_req_valid                   (vif.patternReaderIo_req_valid),
    .io_patternReaderIo_req_bits_patternType        (vif.patternReaderIo_req_bits_patternType),
    .io_patternReaderIo_req_bits_done               (vif.patternReaderIo_req_bits_done),
    .io_patternReaderIo_req_bits_clear              (vif.patternReaderIo_req_bits_clear),
    .io_patternReaderIo_resp_valid                  (vif.patternReaderIo_resp_valid),
    // 16-bit packed bus split to individual DUT inputs
    .io_patternReaderIo_resp_bits_perLaneStatusBits_0  (vif.patternReaderIo_resp_bits_perLaneStatusBits[0]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_1  (vif.patternReaderIo_resp_bits_perLaneStatusBits[1]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_2  (vif.patternReaderIo_resp_bits_perLaneStatusBits[2]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_3  (vif.patternReaderIo_resp_bits_perLaneStatusBits[3]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_4  (vif.patternReaderIo_resp_bits_perLaneStatusBits[4]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_5  (vif.patternReaderIo_resp_bits_perLaneStatusBits[5]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_6  (vif.patternReaderIo_resp_bits_perLaneStatusBits[6]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_7  (vif.patternReaderIo_resp_bits_perLaneStatusBits[7]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_8  (vif.patternReaderIo_resp_bits_perLaneStatusBits[8]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_9  (vif.patternReaderIo_resp_bits_perLaneStatusBits[9]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_10 (vif.patternReaderIo_resp_bits_perLaneStatusBits[10]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_11 (vif.patternReaderIo_resp_bits_perLaneStatusBits[11]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_12 (vif.patternReaderIo_resp_bits_perLaneStatusBits[12]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_13 (vif.patternReaderIo_resp_bits_perLaneStatusBits[13]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_14 (vif.patternReaderIo_resp_bits_perLaneStatusBits[14]),
    .io_patternReaderIo_resp_bits_perLaneStatusBits_15 (vif.patternReaderIo_resp_bits_perLaneStatusBits[15]),
    .io_patternReaderIo_resp_bits_aggregateStatus      (vif.patternReaderIo_resp_bits_aggregateStatus),

    // TxPtTest Requester
    .io_txPtTestReqInterfaceIo_done                    (vif.txPtTestReqIo_done),
    .io_txPtTestReqInterfaceIo_ptTestResults_valid      (vif.txPtTestReqIo_ptTestResults_valid),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_0    (vif.txPtTestReqIo_ptTestResults_bits[0]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_1    (vif.txPtTestReqIo_ptTestResults_bits[1]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_2    (vif.txPtTestReqIo_ptTestResults_bits[2]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_3    (vif.txPtTestReqIo_ptTestResults_bits[3]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_4    (vif.txPtTestReqIo_ptTestResults_bits[4]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_5    (vif.txPtTestReqIo_ptTestResults_bits[5]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_6    (vif.txPtTestReqIo_ptTestResults_bits[6]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_7    (vif.txPtTestReqIo_ptTestResults_bits[7]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_8    (vif.txPtTestReqIo_ptTestResults_bits[8]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_9    (vif.txPtTestReqIo_ptTestResults_bits[9]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_10   (vif.txPtTestReqIo_ptTestResults_bits[10]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_11   (vif.txPtTestReqIo_ptTestResults_bits[11]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_12   (vif.txPtTestReqIo_ptTestResults_bits[12]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_13   (vif.txPtTestReqIo_ptTestResults_bits[13]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_14   (vif.txPtTestReqIo_ptTestResults_bits[14]),
    .io_txPtTestReqInterfaceIo_ptTestResults_bits_15   (vif.txPtTestReqIo_ptTestResults_bits[15]),
    .io_txPtTestReqInterfaceIo_start                   (vif.txPtTestReqIo_start),

    // TxPtTest Responder
    .io_txPtTestRespInterfaceIo_done       (vif.txPtTestRespIo_done),
    .io_txPtTestRespInterfaceIo_start      (vif.txPtTestRespIo_start)
  );

  // -------------------------------------------------------------------------
  // Pass 3 bidirectional bridge between mbinit_if (DUT) and the split VIP
  // interfaces. The DUT instantiation above is untouched (still on vif).
  //   * DUT outputs  : split <= vif   (mirror, for monitors)
  //   * DUT inputs   : vif   <= split (the new split drivers/stubs reach the DUT)
  // The DUT-input direction was the Pass 2 ICDCBA culprit (a clocking output
  // continuously assigned); flipping it to vif <= split makes the split signal's
  // sole driver the new driver's clocking block. The legacy driver no longer
  // drives vif (env factory-overrides it with mbinit_legacy_adapter).
  // mb_reset_if observes the combined `reset` through its port; reset_req stays
  // undriven until Pass 6.
  // TODO(pass>=8/9): once tests run on env.vseqr and the legacy facade is
  // retired, move the DUT ports onto the split interfaces and delete this bridge.
  // -------------------------------------------------------------------------
  // Requester sideband lane
  assign req_if.tx_valid     = vif.requesterSbLaneIo_tx_valid;       // DUT out -> split
  assign req_if.tx_bits_data = vif.requesterSbLaneIo_tx_bits_data;   // DUT out -> split
  assign req_if.rx_ready     = vif.requesterSbLaneIo_rx_ready;       // DUT out -> split
  assign vif.requesterSbLaneIo_tx_ready     = req_if.tx_ready;       // split -> DUT in
  assign vif.requesterSbLaneIo_rx_valid     = req_if.rx_valid;       // split -> DUT in
  assign vif.requesterSbLaneIo_rx_bits_data = req_if.rx_bits_data;   // split -> DUT in
  // Responder sideband lane
  assign rsp_if.tx_valid     = vif.responderSbLaneIo_tx_valid;       // DUT out -> split
  assign rsp_if.tx_bits_data = vif.responderSbLaneIo_tx_bits_data;   // DUT out -> split
  assign rsp_if.rx_ready     = vif.responderSbLaneIo_rx_ready;       // DUT out -> split
  assign vif.responderSbLaneIo_tx_ready     = rsp_if.tx_ready;       // split -> DUT in
  assign vif.responderSbLaneIo_rx_valid     = rsp_if.rx_valid;       // split -> DUT in
  assign vif.responderSbLaneIo_rx_bits_data = rsp_if.rx_bits_data;   // split -> DUT in
  // FSM control: start + local PHY settings driven from split; status mirrored.
  assign vif.fsmCtrl_start                  = ctrl_if.fsmCtrl_start;            // split -> DUT in
  assign vif.localPhySettings_valid        = ctrl_if.localPhySettings_valid;        // split -> DUT in
  assign vif.localPhySettings_voltageSwing = ctrl_if.localPhySettings_voltageSwing; // split -> DUT in
  assign vif.localPhySettings_maxDataRate  = ctrl_if.localPhySettings_maxDataRate;  // split -> DUT in
  assign vif.localPhySettings_clockMode    = ctrl_if.localPhySettings_clockMode;    // split -> DUT in
  assign vif.localPhySettings_clockPhase   = ctrl_if.localPhySettings_clockPhase;   // split -> DUT in
  assign vif.localPhySettings_ucieSx8      = ctrl_if.localPhySettings_ucieSx8;      // split -> DUT in
  assign vif.localPhySettings_sbFeatExt    = ctrl_if.localPhySettings_sbFeatExt;    // split -> DUT in
  assign vif.localPhySettings_txAdjRuntime = ctrl_if.localPhySettings_txAdjRuntime; // split -> DUT in
  assign vif.localPhySettings_moduleId     = ctrl_if.localPhySettings_moduleId;     // split -> DUT in
  assign ctrl_if.fsmCtrl_substateTransitioning = vif.fsmCtrl_substateTransitioning; // DUT out -> split
  assign ctrl_if.fsmCtrl_error                 = vif.fsmCtrl_error;
  assign ctrl_if.fsmCtrl_done                  = vif.fsmCtrl_done;
  assign ctrl_if.negotiatedPhySettings_valid       = vif.negotiatedPhySettings_valid;
  assign ctrl_if.negotiatedPhySettings_voltageSwing= vif.negotiatedPhySettings_voltageSwing;
  assign ctrl_if.negotiatedPhySettings_maxDataRate = vif.negotiatedPhySettings_maxDataRate;
  assign ctrl_if.negotiatedPhySettings_clockMode   = vif.negotiatedPhySettings_clockMode;
  assign ctrl_if.negotiatedPhySettings_clockPhase  = vif.negotiatedPhySettings_clockPhase;
  assign ctrl_if.negotiatedPhySettings_moduleId    = vif.negotiatedPhySettings_moduleId;
  assign ctrl_if.currentState                = vif.currentState;
  assign ctrl_if.interoperableParamsNotFound = vif.interoperableParamsNotFound;
  assign ctrl_if.usingPatternWriter          = vif.usingPatternWriter;
  assign ctrl_if.usingPatternReader          = vif.usingPatternReader;
  assign ctrl_if.applyLaneReversal           = vif.applyLaneReversal;
  assign ctrl_if.localFunctionalLanes        = vif.localFunctionalLanes;
  assign ctrl_if.txWidthChanged              = vif.txWidthChanged;
  assign ctrl_if.remoteFunctionalLanes       = vif.remoteFunctionalLanes;
  assign ctrl_if.rxWidthChanged              = vif.rxWidthChanged;
  // Calibration handshake
  assign cal_if.cal_start = vif.mbInitCalStart;   // DUT out -> split
  assign vif.mbInitCalDone = cal_if.cal_done;     // split -> DUT in
  // PatternWriter service
  assign pw_if.req_valid       = vif.patternWriterIo_req_valid;             // DUT out -> split
  assign pw_if.req_patternType = vif.patternWriterIo_req_bits_patternType;  // DUT out -> split
  assign vif.patternWriterIo_req_ready     = pw_if.req_ready;               // split -> DUT in
  assign vif.patternWriterIo_resp_complete = pw_if.resp_complete;           // split -> DUT in
  // PatternReader service
  assign pr_if.req_valid       = vif.patternReaderIo_req_valid;             // DUT out -> split
  assign pr_if.req_patternType = vif.patternReaderIo_req_bits_patternType;  // DUT out -> split
  assign pr_if.req_done        = vif.patternReaderIo_req_bits_done;         // DUT out -> split
  assign pr_if.req_clear       = vif.patternReaderIo_req_bits_clear;        // DUT out -> split
  assign vif.patternReaderIo_req_ready                  = pr_if.req_ready;       // split -> DUT in
  assign vif.patternReaderIo_resp_valid                 = pr_if.resp_valid;      // split -> DUT in
  assign vif.patternReaderIo_resp_bits_perLaneStatusBits = pr_if.resp_perLane;   // split -> DUT in
  assign vif.patternReaderIo_resp_bits_aggregateStatus  = pr_if.resp_aggregate;  // split -> DUT in
  // Tx point-test (requester)
  assign pttest_req_if.start = vif.txPtTestReqIo_start;                          // DUT out -> split
  assign vif.txPtTestReqIo_done                 = pttest_req_if.done;            // split -> DUT in
  assign vif.txPtTestReqIo_ptTestResults_valid  = pttest_req_if.results_valid;   // split -> DUT in
  assign vif.txPtTestReqIo_ptTestResults_bits   = pttest_req_if.results_bits;    // split -> DUT in
  // Tx point-test (responder)
  assign pttest_rsp_if.start = vif.txPtTestRespIo_start;                         // DUT out -> split
  assign vif.txPtTestRespIo_done = pttest_rsp_if.done;                           // split -> DUT in
  // Mainband lane control (observe-only, XC-05)
  assign lane_ctrl_if.tx_data_en  = vif.mbLaneCtrl_txDataEn;
  assign lane_ctrl_if.tx_clk_en   = vif.mbLaneCtrl_txClkEn;
  assign lane_ctrl_if.tx_valid_en = vif.mbLaneCtrl_txValidEn;
  assign lane_ctrl_if.tx_track_en = vif.mbLaneCtrl_txTrackEn;
  assign lane_ctrl_if.rx_data_en  = vif.mbLaneCtrl_rxDataEn;
  assign lane_ctrl_if.rx_clk_en   = vif.mbLaneCtrl_rxClkEn;
  assign lane_ctrl_if.rx_valid_en = vif.mbLaneCtrl_rxValidEn;
  assign lane_ctrl_if.rx_track_en = vif.mbLaneCtrl_rxTrackEn;

`ifdef MBINIT_RM05_DEBUG
  // Hierarchical probe: MBInitRequester (see MBInitRequester.sv). Gated by +define+MBINIT_RM05_DEBUG.
  logic [10:0] rm05_dbg_prev;

  always_ff @(posedge clock) begin
    automatic logic [10:0] p;
    if (reset)
      rm05_dbg_prev <= '1;
    else begin
      p = {
        dut.requester.currentState,
        dut.requester.substateReg,
        dut.requester.faultInLowerLanes,
        dut.requester.faultInUpperLanes,
        dut.requester.allLanesFailed,
        dut.requester._sbMsgExchanger_io_msgSent,
        dut.requester.errorDetectedWire
      };
      if (dut.requester.currentState == 3'h5) begin
        if (p != rm05_dbg_prev) begin
          $display(
            "[MBINIT_RM05_DBG] %0t REPAIRMB subst=%0d fl=%b fu=%b alf=%b msgSent=%b errWire=%b ltf=%0d ptStart=%b ptValid=%b twc=%b fsm_err=%b",
            $time,
            dut.requester.substateReg,
            dut.requester.faultInLowerLanes,
            dut.requester.faultInUpperLanes,
            dut.requester.allLanesFailed,
            dut.requester._sbMsgExchanger_io_msgSent,
            dut.requester.errorDetectedWire,
            dut.requester.localTxFunctionalLanesReg,
            dut.requester.io_txPtTestReqInterfaceIo_start,
            dut.requester.io_txPtTestReqInterfaceIo_ptTestResults_valid,
            dut.requester.io_txWidthChanged,
            vif.fsmCtrl_error);
          rm05_dbg_prev <= p;
        end
      end
      else
        rm05_dbg_prev <= '1;
    end
  end
`endif

  initial begin
    uvm_config_db#(virtual mbinit_if)::set(null, "*", "mbinit_vif", vif);
    // Pass 2: publish the split interfaces for the Pass 4 monitors. No component
    // fetches these yet, so this is additive and behavior-neutral.
    uvm_config_db#(virtual mb_ctrl_if)::set          (null, "*", "mbinit_ctrl_vif",       ctrl_if);
    uvm_config_db#(virtual mb_req_if)::set           (null, "*", "mbinit_req_vif",        req_if);
    uvm_config_db#(virtual mb_rsp_if)::set           (null, "*", "mbinit_rsp_vif",        rsp_if);
    uvm_config_db#(virtual mb_reset_if)::set         (null, "*", "mbinit_reset_vif",      rst_if);
    uvm_config_db#(virtual mb_cal_if)::set           (null, "*", "mbinit_cal_vif",        cal_if);
    uvm_config_db#(virtual mb_pattern_writer_if)::set(null, "*", "mbinit_pw_vif",         pw_if);
    uvm_config_db#(virtual mb_pattern_reader_if)::set(null, "*", "mbinit_pr_vif",         pr_if);
    uvm_config_db#(virtual mb_pttest_req_if)::set    (null, "*", "mbinit_pttest_req_vif", pttest_req_if);
    uvm_config_db#(virtual mb_pttest_rsp_if)::set    (null, "*", "mbinit_pttest_rsp_vif", pttest_rsp_if);
    uvm_config_db#(virtual mb_lane_ctrl_if)::set     (null, "*", "mbinit_lane_ctrl_vif",  lane_ctrl_if);
    run_test();
  end

endmodule
