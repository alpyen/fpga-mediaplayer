library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.ceil;

library unisim;
use unisim.vcomponents.all;

entity fpga_mediaplayer is
    generic (
        SIMULATION: boolean := false;

        WIDTH: positive := 32;
        HEIGHT: positive := 24
    );
    port (
        clock100mhz: in std_ulogic;
        reset: in std_ulogic;

        start_button: in std_ulogic;

        -- SPI ports
        spi_sclk: inout std_ulogic; -- This is not inout, read comment at process "tb_specifics".
        spi_cs_n: out std_ulogic;

        spi_sdi: inout std_logic; -- out
        spi_sdo: inout std_logic; -- in

        spi_wp_n: inout std_logic; -- out
        spi_hold_n: inout std_logic; -- out

        -- I2S interface to I2S2 PMOD
        i2s_mclk: out std_ulogic;
        i2s_lrck: out std_ulogic;
        i2s_sclk: out std_ulogic;
        i2s_sdin: out std_ulogic;

        -- Board interface to LED Board
        board_row_data: out std_ulogic;
        board_shift_row_data: out std_ulogic;
        board_apply_row_and_strobe: out std_ulogic;
        board_row_strobe: out std_ulogic;
        board_shift_row_strobe: out std_ulogic;
        board_output_enable_n: out std_ulogic
    );
end entity;

architecture tle of fpga_mediaplayer is
    signal clock10mhz: std_ulogic;
    signal clock_i2s_mclk: std_ulogic;

    component clocking_wizard
        port (
            clock100mhz : in std_ulogic;
            reset : in std_ulogic;
            clock10mhz : out std_ulogic;
            clock11_2896mhz: out std_ulogic;
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

    component fifo_video
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
    signal audio_driver_play: std_ulogic;
    signal audio_driver_done: std_ulogic;

    -- Audio Fifo
    signal audio_fifo_write_enable: std_ulogic;
    signal audio_fifo_data_in_slv: std_logic_vector(7 downto 0);
    signal audio_fifo_data_in: std_ulogic_vector(audio_fifo_data_in_slv'range);
    signal audio_fifo_full: std_ulogic;

    signal audio_fifo_read_enable: std_ulogic;
    signal audio_fifo_data_out_slv: std_logic_vector(0 downto 0);
    signal audio_fifo_data_out: std_ulogic_vector(audio_fifo_data_out_slv'range);
    signal audio_fifo_empty: std_ulogic;

    -- Video Driver Signals
    signal video_driver_play: std_ulogic;
    signal video_driver_done: std_ulogic;

    -- Video Fifo
    signal video_fifo_write_enable: std_ulogic;
    signal video_fifo_data_in_slv: std_logic_vector(7 downto 0);
    signal video_fifo_data_in: std_ulogic_vector(video_fifo_data_in_slv'range);
    signal video_fifo_full: std_ulogic;

    signal video_fifo_read_enable: std_ulogic;
    signal video_fifo_data_out_slv: std_logic_vector(0 downto 0);
    signal video_fifo_data_out: std_ulogic_vector(video_fifo_data_out_slv'range);
    signal video_fifo_empty: std_ulogic;
begin
    assert memory_driver_address'length <= 32
    report "Memory addresses exceed file specification of 32 bits."
    severity failure;

    -- SPI SCLK is not directly drivable on Artix7 devices
    -- it has to be accessed through the STARTUPE2 primitive.
    -- Technically we could route clock10mhz immediately to USRCCLKO
    -- instead of routing it into the spi_memory_driver and then to it
    -- but this way it's more consistent and Vivado shortens it anyway.
    -- This is also the reason why there is a port called spi_sclk in the tle
    -- so it's easier for other boards to set up whose SPI SCLK pin is freely accessible.
    STARTUPE2_inst: STARTUPE2
    generic map (
        PROG_USR      => "FALSE",
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
        USRCCLKO  => spi_sclk,
        USRCCLKTS => '0',
        USRDONEO  => '1',
        USRDONETS => '0'
    );

    clocking_wizard_inst: clocking_wizard
    port map (
        clock100mhz     => clock100mhz,
        reset           => '0',
        clock10mhz      => clock10mhz,
        clock11_2896mhz => clock_i2s_mclk,
        locked          => open
    );

    reset_debouncer: entity work.debouncer
    generic map (
        COUNT => DEBOUNCE_THRESHHOLD
    )
    port map (
        clock  => clock10mhz,
        input  => reset,
        output => reset_debounced
    );

    start_debouncer: entity work.debouncer
    generic map (
        COUNT => DEBOUNCE_THRESHHOLD
    )
    port map (
        clock  => clock10mhz,
        input  => start_button,
        output => start_debounced
    );

    -- Override signals that need to be handled differently in the simulation.
    -- For example we don't need to debounce the buttons as those are sampled
    -- every 100ms, this is just wasted simulation time.
    --
    -- Another important note is that the port spi_sclk is defined as "inout"
    -- even though it should be only "out". It's completely unnecessary on the Artix7
    -- but that's a different story.
    -- The reason why we don't use "out" and an internal signal is that this
    -- causes the simulator to freak out and generate delta races due to
    -- the renaming of the clock onto a different signal.
    -- It would synthesize fine, but the simulation is garbage.
    tb_specifics: process (reset, start_button, reset_debounced, start_debounced)
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
        sclk    => spi_sclk,
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

    fifo_video_inst: fifo_video
    port map (
        clk   => clock10mhz,
        srst  => reset_final,
        din   => video_fifo_data_in_slv,
        wr_en => video_fifo_write_enable,
        rd_en => video_fifo_read_enable,
        dout  => video_fifo_data_out_slv,
        full  => video_fifo_full,
        empty => video_fifo_empty
    );

    video_fifo_data_in_slv <= std_logic_vector(video_fifo_data_in);
    video_fifo_data_out <= std_ulogic_vector(video_fifo_data_out_slv);

    control_unit_inst: entity work.control_unit
    generic map (
        WIDTH => WIDTH,
        HEIGHT => HEIGHT
    )
    port map (
        clock                   => clock10mhz,
        reset                   => reset_final,

        start                   => start_final,

        media_base_address      => (others => '0'),

        -- Memory Driver Interface
        memory_driver_start     => memory_driver_start,
        memory_driver_address   => memory_driver_address,
        memory_driver_data      => memory_driver_data,
        memory_driver_done      => memory_driver_done,

        -- Audio Driver Interface
        audio_driver_play       => audio_driver_play,
        audio_driver_done       => audio_driver_done,

        -- Audio Fifo
        audio_fifo_write_enable => audio_fifo_write_enable,
        audio_fifo_data_in      => audio_fifo_data_in,
        audio_fifo_full         => audio_fifo_full,

        -- Video Driver Interface
        video_driver_play       => video_driver_play,
        video_driver_done       => video_driver_done,

        -- Video Fifo
        video_fifo_write_enable => video_fifo_write_enable,
        video_fifo_data_in      => video_fifo_data_in,
        video_fifo_full         => video_fifo_full
    );

    i2s_mclk <= clock_i2s_mclk;

    audio_driver_inst: entity work.audio_driver
    generic map (
        CLOCK_SPEED    => 10_000_000,
        I2S_MCLK_SPEED => 11_289_600
    )
    port map (
        clock                  => clock10mhz,
        reset                  => reset_final,

        -- Audio Driver Interface
        audio_driver_play      => audio_driver_play,
        audio_driver_done      => audio_driver_done,

        -- Audio Fifo
        audio_fifo_read_enable => audio_fifo_read_enable,
        audio_fifo_data_out    => audio_fifo_data_out,
        audio_fifo_empty       => audio_fifo_empty,

        -- I2S Interface
        i2s_mclk               => clock_i2s_mclk,
        i2s_lrck               => i2s_lrck,
        i2s_sclk               => i2s_sclk,
        i2s_sdin               => i2s_sdin
    );

    video_driver_inst: entity work.video_driver
    generic map (
        CLOCK_SPEED => 10_000_000,
        WIDTH       => WIDTH,
        HEIGHT      => HEIGHT
    )
    port map (
        clock                      => clock10mhz,
        reset                      => reset,

        -- Video Driver Interface
        video_driver_play          => video_driver_play,
        video_driver_done          => video_driver_done,

        -- Video Fifo
        video_fifo_read_enable     => video_fifo_read_enable,
        video_fifo_data_out        => video_fifo_data_out,
        video_fifo_empty           => video_fifo_empty,

        -- Board interface to LED Board
        board_row_data             => board_row_data,
        board_shift_row_data       => board_shift_row_data,
        board_apply_row_and_strobe => board_apply_row_and_strobe,
        board_row_strobe           => board_row_strobe,
        board_shift_row_strobe     => board_shift_row_strobe,
        board_output_enable_n      => board_output_enable_n
    );
end architecture;
