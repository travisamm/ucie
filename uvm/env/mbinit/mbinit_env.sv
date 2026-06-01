`ifndef MBINIT_ENV_SV
`define MBINIT_ENV_SV

// ---------------------------------------------------------------------------
// mbinit_env  (Pass 5)
// ---------------------------------------------------------------------------
// Legacy drive facade + event-driven checking:
//   * agent (mbinit_agent): legacy sequencer + driver + monitor. The driver is
//     factory-overridden to mbinit_legacy_adapter, so env.agent.driver is still
//     a mbinit_driver (the rm02/rm07/rm05 tests' $cast + flag-set keep working)
//     but it decomposes each mbinit_transaction onto the new split sequencers
//     instead of driving the monolithic vif.
//   * new split drive components drive the split interfaces (which tb_top
//     bridges to the DUT): requester/responder RX drivers, FSM-control driver,
//     and autonomous cal/pattern-writer/pattern-reader/point-test stubs.
//   * the 10 event-producing monitors (Pass 4) now feed the EVENT-DRIVEN
//     scoreboard + coverage (Pass 5). The legacy agent.monitor is still
//     instantiated but its analysis port is left UNCONNECTED (retired with the
//     rest of the legacy facade in Pass 8). The mbinit_event_audit subscriber
//     stays connected as a passive diagnostic.
//
// cfg: mbinit_env_cfg is published to the scoreboard before it is built, so the
// scoreboard pulls its expect_* defaults from cfg; tests may still mutate
// env.scoreboard.expect_* afterward.
//
// TODO(pass 8): once tests run on env.vseqr, retire the legacy agent + adapter
// + legacy mbinit_monitor.
// ---------------------------------------------------------------------------
class mbinit_env extends uvm_env;
  `uvm_component_utils(mbinit_env)

  // Legacy facade
  mbinit_agent      agent;
  mbinit_scoreboard scoreboard;
  mbinit_coverage   coverage;
  mbinit_env_cfg    cfg;

  // New split drive path (Pass 3)
  mbinit_req_rx_driver     req_rx_driver;
  mbinit_rx_sequencer      req_rx_seqr;
  mbinit_rsp_rx_driver     rsp_rx_driver;
  mbinit_rx_sequencer      rsp_rx_seqr;
  mbinit_ctrl_driver       ctrl_driver;
  mbinit_ctrl_sequencer    ctrl_seqr;
  mbinit_cal_stub          cal_stub;
  mbinit_pw_stub           pw_stub;
  mbinit_pr_stub           pr_stub;
  mbinit_pttest_req_stub   pttest_req_stub;
  mbinit_pttest_rsp_stub   pttest_rsp_stub;
  mbinit_service_cfg       svc_cfg;
  mbinit_virtual_sequencer vseqr;

  // Pass 6: sequence-driven reset injection.
  mbinit_reset_driver      reset_driver;
  mbinit_reset_sequencer   reset_seqr;
  // Pass 6: lane vifs, so the env can push the payload-stability SVA opt-in
  // (cfg.req_stable_chk_en / rsp_stable_chk_en) onto each interface's
  // stable_chk_en bit at start_of_simulation.
  virtual mb_req_if        req_vif;
  virtual mb_rsp_if        rsp_vif;

  // Pass 4: event-producing monitors + passive audit subscriber (shadow stream;
  // legacy monitor/scoreboard/coverage stay authoritative).
  mbinit_req_monitor        evt_req_mon;
  mbinit_rsp_monitor        evt_rsp_mon;
  mbinit_ctrl_monitor       evt_ctrl_mon;
  mbinit_reset_monitor      evt_reset_mon;
  mbinit_cal_monitor        evt_cal_mon;
  mbinit_pw_monitor         evt_pw_mon;
  mbinit_pr_monitor         evt_pr_mon;
  mbinit_pttest_req_monitor evt_pttest_req_mon;
  mbinit_pttest_rsp_monitor evt_pttest_rsp_mon;
  mbinit_lane_ctrl_monitor  evt_lane_ctrl_mon;
  mbinit_event_audit        evt_audit;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Route the legacy agent's driver to the adapter (must precede agent build).
    mbinit_driver::type_id::set_type_override(mbinit_legacy_adapter::get_type());

    // Publish the env cfg to the scoreboard BEFORE it is built so it can pull
    // its expect_* defaults. Tests may still mutate env.scoreboard.expect_*.
    cfg = mbinit_env_cfg::type_id::create("cfg");
    uvm_config_db#(mbinit_env_cfg)::set(this, "scoreboard", "cfg", cfg);

    agent      = mbinit_agent::type_id::create("agent", this);
    scoreboard = mbinit_scoreboard::type_id::create("scoreboard", this);
    coverage   = mbinit_coverage::type_id::create("coverage", this);

    // Shared service policy, published for the service stubs.
    svc_cfg = mbinit_service_cfg::type_id::create("svc_cfg");
    uvm_config_db#(mbinit_service_cfg)::set(this, "*", "mbinit_svc_cfg", svc_cfg);

    // New split drive components.
    req_rx_driver   = mbinit_req_rx_driver::type_id::create("req_rx_driver", this);
    req_rx_seqr     = mbinit_rx_sequencer::type_id::create("req_rx_seqr", this);
    rsp_rx_driver   = mbinit_rsp_rx_driver::type_id::create("rsp_rx_driver", this);
    rsp_rx_seqr     = mbinit_rx_sequencer::type_id::create("rsp_rx_seqr", this);
    ctrl_driver     = mbinit_ctrl_driver::type_id::create("ctrl_driver", this);
    ctrl_seqr       = mbinit_ctrl_sequencer::type_id::create("ctrl_seqr", this);
    cal_stub        = mbinit_cal_stub::type_id::create("cal_stub", this);
    pw_stub         = mbinit_pw_stub::type_id::create("pw_stub", this);
    pr_stub         = mbinit_pr_stub::type_id::create("pr_stub", this);
    pttest_req_stub = mbinit_pttest_req_stub::type_id::create("pttest_req_stub", this);
    pttest_rsp_stub = mbinit_pttest_rsp_stub::type_id::create("pttest_rsp_stub", this);
    vseqr           = mbinit_virtual_sequencer::type_id::create("vseqr", this);

    // Pass 6: reset-injection driver + sequencer.
    reset_driver = mbinit_reset_driver::type_id::create("reset_driver", this);
    reset_seqr   = mbinit_reset_sequencer::type_id::create("reset_seqr", this);

    // Pass 6: grab the lane vifs for the payload-stability SVA opt-in push.
    if (!uvm_config_db#(virtual mb_req_if)::get(this, "", "mbinit_req_vif", req_vif))
      `uvm_fatal("MBINIT_ENV", "mbinit_req_vif not set")
    if (!uvm_config_db#(virtual mb_rsp_if)::get(this, "", "mbinit_rsp_vif", rsp_vif))
      `uvm_fatal("MBINIT_ENV", "mbinit_rsp_vif not set")

    // Pass 4 event producers + audit subscriber.
    evt_req_mon         = mbinit_req_monitor::type_id::create("evt_req_mon", this);
    evt_rsp_mon         = mbinit_rsp_monitor::type_id::create("evt_rsp_mon", this);
    evt_ctrl_mon        = mbinit_ctrl_monitor::type_id::create("evt_ctrl_mon", this);
    evt_reset_mon       = mbinit_reset_monitor::type_id::create("evt_reset_mon", this);
    evt_cal_mon         = mbinit_cal_monitor::type_id::create("evt_cal_mon", this);
    evt_pw_mon          = mbinit_pw_monitor::type_id::create("evt_pw_mon", this);
    evt_pr_mon          = mbinit_pr_monitor::type_id::create("evt_pr_mon", this);
    evt_pttest_req_mon  = mbinit_pttest_req_monitor::type_id::create("evt_pttest_req_mon", this);
    evt_pttest_rsp_mon  = mbinit_pttest_rsp_monitor::type_id::create("evt_pttest_rsp_mon", this);
    evt_lane_ctrl_mon   = mbinit_lane_ctrl_monitor::type_id::create("evt_lane_ctrl_mon", this);
    evt_audit           = mbinit_event_audit::type_id::create("evt_audit", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    mbinit_legacy_adapter ad;
    super.connect_phase(phase);

    // Pass 5: the legacy agent.monitor is intentionally left UNCONNECTED; the
    // event-driven scoreboard + coverage are fed by the Pass 4 monitors below.

    // New drivers <-> their sequencers.
    req_rx_driver.seq_item_port.connect(req_rx_seqr.seq_item_export);
    rsp_rx_driver.seq_item_port.connect(rsp_rx_seqr.seq_item_export);
    ctrl_driver.seq_item_port.connect(ctrl_seqr.seq_item_export);
    // Pass 6: reset driver pulls from the env-level reset sequencer.
    reset_driver.seq_item_port.connect(reset_seqr.seq_item_export);

    // Virtual sequencer handles (for Pass 8 vseqs).
    vseqr.req_rx_seqr = req_rx_seqr;
    vseqr.rsp_rx_seqr = rsp_rx_seqr;
    vseqr.ctrl_seqr   = ctrl_seqr;
    vseqr.reset_seqr  = reset_seqr;

    // Wire the legacy adapter to the split sequencers + service policy.
    if (!$cast(ad, agent.driver))
      `uvm_fatal("MBINIT_ENV",
                 "agent.driver is not mbinit_legacy_adapter (factory override failed?)")
    ad.req_rx_seqr = req_rx_seqr;
    ad.rsp_rx_seqr = rsp_rx_seqr;
    ad.ctrl_seqr   = ctrl_seqr;
    ad.svc_cfg     = svc_cfg;

    // Pass 5: fan all 10 event producers into the scoreboard, coverage, and the
    // (passive, diagnostic) audit subscriber.
    connect_event_producer(evt_req_mon.ev_ap);
    connect_event_producer(evt_rsp_mon.ev_ap);
    connect_event_producer(evt_ctrl_mon.ev_ap);
    connect_event_producer(evt_reset_mon.ev_ap);
    connect_event_producer(evt_cal_mon.ev_ap);
    connect_event_producer(evt_pw_mon.ev_ap);
    connect_event_producer(evt_pr_mon.ev_ap);
    connect_event_producer(evt_pttest_req_mon.ev_ap);
    connect_event_producer(evt_pttest_rsp_mon.ev_ap);
    connect_event_producer(evt_lane_ctrl_mon.ev_ap);
  endfunction

  // Wire one monitor's event port to all three consumers.
  protected function void connect_event_producer(uvm_analysis_port #(mbinit_event) ap);
    ap.connect(scoreboard.ev_export);
    ap.connect(coverage.analysis_export);
    ap.connect(evt_audit.analysis_export);
  endfunction

  // Pass 6: push the per-lane payload-stability SVA opt-in onto each lane
  // interface's stable_chk_en bit. Done at start_of_simulation (top-down) so a
  // Pass 8 test that sets env.cfg.{req,rsp}_stable_chk_en in its own
  // start_of_simulation (which runs before this, the env being the child) is
  // honored. Default cfg = 0 keeps the checker dormant for the legacy tests.
  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (cfg != null) begin
      req_vif.stable_chk_en = cfg.req_stable_chk_en;
      rsp_vif.stable_chk_en = cfg.rsp_stable_chk_en;
    end
  endfunction

endclass
`endif
