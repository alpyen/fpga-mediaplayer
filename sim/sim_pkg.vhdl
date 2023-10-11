-- Simulation helper package
-- Bundles up some commonly used functions used in testbenches

package sim_pkg is
    shared variable clock_duration: time;

    -- Sets the base time the sim procedures will operate on
    procedure sim_setup (clock_duration: time);

    -- Steps (waits) one half clock cycle
    procedure sim_halfstep;

    -- Steps (waits) one full clock cycle
    procedure sim_step;

    -- Steps (waits) a given amount of clock cycles
    procedure sim_wait (clock_cycles: integer := 1);

    -- Ends the simulation with a failed assertion
    procedure sim_done;
end package;

package body sim_pkg is
    procedure sim_setup(clock_duration: time) is
    begin
        sim_pkg.clock_duration := clock_duration;
    end procedure;

    procedure sim_halfstep is
    begin
        wait for clock_duration / 2;
    end procedure;

    procedure sim_step is
    begin
        wait for clock_duration;  
    end procedure;

    procedure sim_wait (clock_cycles: integer := 1) is
    begin
        wait for clock_cycles * clock_duration;
    end procedure;

    procedure sim_done is
    begin
        assert false report "Simulation done!" severity failure;
    end procedure;
end package body;
