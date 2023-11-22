library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.ceil;

library unisim;
use unisim.vcomponents.all;

entity fpga_mediaplayer is
    generic (
        SIMULATION: boolean := false
    );
    port (
        clock100mhz: in std_ulogic;
        reset: in std_ulogic;
        
        -- SPI ports
        spi_sclk: out std_ulogic;
        spi_cs_n: out std_ulogic;

        spi_sdi: inout std_ulogic;
        spi_sdo: inout std_ulogic;
        
        spi_wp_n: inout std_ulogic;
        spi_hold_n: inout std_ulogic;
        
        start_button: in std_ulogic
    );
end entity;

architecture tle of fpga_mediaplayer is
    signal clock10mhz: std_ulogic;

    -- PLL/MMCM to generate all the necessary clocks from the base 100 MHz
    -- The following clocks are necessary:
    --      10 MHz FPGA Fabric
    --      10 MHz SPI Flash
    --      ?? MHz I2S Clocks (MCLK, SCLK, LRCLK)
    component clocking_wizard
        port (
            clock100mhz : in  std_ulogic;
            reset : in std_ulogic;
            clock10mhz : out std_ulogic;
            locked : out std_ulogic
        );
    end component;

    component fifo_audio
        port (
            clk : in std_logic;
            srst : in std_logic;
            din : in std_logic_vector(7 downto 0);
            wr_en : in std_logic;
            rd_en : in std_logic;
            dout : out std_logic_vector(0 downto 0);
            full : out std_logic;
            empty : out std_logic 
        );
    end component;

    -- SPI SCLK is not directly drivable on Artix7 devices
    -- it has to be accessed through the STARTUPE2 primitive.
    -- Technically we could route clock10mhz immediately to USRCCLKO
    -- instead of routing it into the spi_memory_driver and then to it
    -- but this way it's more consistent and Vivado shortens it anyway.
    -- This is also the reason why there is a port called spi_sclk in the tle
    -- so it's easier for other boards to set up whose SPI SCLK pin is freely accessible.
    signal spi_sclk_int: std_ulogic;

    -- Button state has to remain for 100 ms
    constant DEBOUNCE_THRESHHOLD: positive := integer(ceil(real(10e6) * (100.0 / 1000.0)));

    signal reset_debounced: std_ulogic;
    signal start_debounced: std_ulogic;

    signal reset_final: std_ulogic;
    signal start_final: std_ulogic;

    -- Memory Driver Signals
    signal memory_driver_start: std_ulogic;
    signal memory_driver_address: std_ulogic_vector(23 downto 0);

    signal memory_driver_done: std_ulogic;
    signal memory_driver_data: std_ulogic_vector(7 downto 0);

    -- Audio Driver Signals
    signal audio_driver_start: std_ulogic;
    
    -- Audio Fifo
    signal audio_fifo_write_enable: std_ulogic;
    signal audio_fifo_data_in_slv: std_logic_vector(7 downto 0);
    signal audio_fifo_data_in: std_ulogic_vector(audio_fifo_data_in_slv'range);
    signal audio_fifo_full: std_ulogic;

    signal audio_fifo_read_enable: std_ulogic;
    signal audio_fifo_data_out_slv: std_logic_vector(0 downto 0);
    signal audio_fifo_data_out: std_ulogic_vector(audio_fifo_data_out_slv'range);
    signal audio_fifo_empty: std_ulogic;
begin
    -- Used to wire up the SCLK for the SPI flash
    STARTUPE2_inst: STARTUPE2
    generic map (
        PROG_USR => "FALSE",
        SIM_CCLK_FREQ => 0.0
    )
    port map (
        CFGCLK    => open,
        CFGMCLK   => open,
        EOS       => open,
        PREQ      => open,
        CLK       => '0',
        GSR       => '0',
        GTS       => '0',
        KEYCLEARB => '1',
        PACK      => '0',
        USRCCLKO  => spi_sclk_int,
        USRCCLKTS => '0',
        USRDONEO  => '1',
        USRDONETS => '0'
    );

    clocking_wizard_inst: clocking_wizard
    port map (
        clock100mhz => clock100mhz,
        reset     => '0',
        clock10mhz  => clock10mhz,
        locked    => open
    );

    reset_debouncer: entity work.debouncer
    generic map (
        COUNT => DEBOUNCE_THRESHHOLD
    )
    port map (
        clk    => clock10mhz,
        input  => reset,
        output => reset_debounced
    );

    start_debouncer: entity work.debouncer
    generic map (
        COUNT => DEBOUNCE_THRESHHOLD
    )
    port map (
        clk    => clock10mhz,
        input  => start_button,
        output => start_debounced
    );

    -- Override signals that need to be handled differently in the simulation.
    -- For example we don't need to debounce the buttons as those are sampled
    -- every 100ms, this is just wasted simulation time.
    spi_sclk <= spi_sclk_int;

    process (reset, start_button, reset_debounced, start_debounced)
    begin
        reset_final <= reset_debounced;
        start_final <= start_debounced;

        if SIMULATION = true then
            reset_final <= reset;
            start_final <= start_button;
        end if;
    end process;

    spi_memory_driver_inst: entity work.spi_memory_driver
    port map (
        clock   => clock10mhz,
        reset   => reset_final,

        -- Memory Driver Interface
        address => memory_driver_address,
        data    => memory_driver_data,

        start   => memory_driver_start,
        done    => memory_driver_done,

        -- SPI Interface
        sclk    => spi_sclk_int,
        cs_n    => spi_cs_n,

        sdi     => spi_sdi,
        sdo     => spi_sdo,

        wp_n    => spi_wp_n,
        hold_n  => spi_hold_n
    );

    fifo_audio_inst: fifo_audio
    port map (
        clk   => clock10mhz,
        srst  => reset_final,
        din   => audio_fifo_data_in_slv,
        wr_en => audio_fifo_write_enable,
        rd_en => audio_fifo_read_enable,
        dout  => audio_fifo_data_out_slv,
        full  => audio_fifo_full,
        empty => audio_fifo_empty
    );

    audio_fifo_data_in_slv <= std_logic_vector(audio_fifo_data_in);
    audio_fifo_data_out <= std_ulogic_vector(audio_fifo_data_out_slv);

    control_unit_inst: entity work.control_unit
    port map (
        clock                   => clock10mhz,
        reset                   => reset_final,

        start                   => start_final,

        -- Memory Driver Interface
        memory_driver_start     => memory_driver_start,
        memory_driver_addr      => memory_driver_address,
        memory_driver_data      => memory_driver_data,
        memory_driver_done      => memory_driver_done,

        -- Audio Driver Interface
        audio_driver_start      => audio_driver_start,

        -- Audio Fifo
        audio_fifo_write_enable => audio_fifo_write_enable,
        audio_fifo_data_in      => audio_fifo_data_in,
        audio_fifo_full         => audio_fifo_full
    );

    audio_driver_inst: entity work.audio_driver
    port map (
        clock                  => clock10mhz,
        reset                  => reset_final,

        -- Audio Driver Interface
        audio_driver_start     => audio_driver_start,

        -- Audio Fifo
        audio_fifo_read_enable => audio_fifo_read_enable,
        audio_fifo_data_out    => audio_fifo_data_out,
        audio_fifo_empty       => audio_fifo_empty
    );

end architecture;
