library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity control_unit is
    port (
        clock: in std_ulogic;
        reset: in std_ulogic;

        start: in std_ulogic;

        -- Memory Driver Interface
        memory_driver_start: out std_ulogic;
        memory_driver_addr: out std_ulogic_vector(23 downto 0);

        memory_driver_data: in std_ulogic_vector(7 downto 0);
        memory_driver_done: in std_ulogic;
        
        -- Audio Driver Interface
        audio_driver_start: out std_ulogic;

        -- Audio Fifo
        audio_fifo_write_enable: out std_ulogic;
        audio_fifo_data_in: out std_ulogic_vector(7 downto 0);
        audio_fifo_full: in std_ulogic
    );
end entity;

architecture arch of control_unit is
    
begin
end architecture;
