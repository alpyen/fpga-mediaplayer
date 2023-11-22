library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_driver is
    port (
        clock: in std_logic;
        reset: in std_ulogic;

        -- Audio Driver Interface
        audio_driver_start: in std_ulogic;

        -- Audio Fifo
        audio_fifo_read_enable: out std_ulogic;
        audio_fifo_data_out: in std_ulogic_vector(0 downto 0);
        audio_fifo_empty: in std_ulogic
    );
end entity;

architecture arch of audio_driver is

begin
    audio_fifo_read_enable <= '0';
end architecture;
