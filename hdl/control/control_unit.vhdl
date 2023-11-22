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
    type state_t is (IDLE, READ_HEADER, PARSE_HEADER, FILL_AUDIO_FIFO);
    signal state, state_next: state_t;

    signal address, address_next: std_ulogic_vector(memory_driver_addr'range);

    signal header, header_next: std_ulogic_vector(10 * 8 - 1 downto 0);
begin
    audio_driver_start <= '0';
    audio_fifo_write_enable <= '0';
    audio_fifo_data_in <= (others => '0');

    seq: process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= IDLE;
                address <= (others => '0');
                header <= (others => '0');
            else
                state <= state_next;
                address <= address_next;
                header <= header_next;
            end if;
        end if;
    end process;

    fsm: process (state, start, address, header, memory_driver_done, memory_driver_data)
        variable i_address: integer;
        variable u_address: unsigned(address'range);
    begin
        u_address := unsigned(address);
        i_address := to_integer(u_address);

        state_next <= state;
        address_next <= address;
        header_next <= header;

        memory_driver_start <= '0';
        memory_driver_addr <= (others => '0');

        case state is
            when IDLE =>
                if start = '1' then
                    state_next <= READ_HEADER;

                    memory_driver_start <= '1';
                    memory_driver_addr <= address;

                    address_next <= std_ulogic_vector(u_address + 1);
                end if;

            when READ_HEADER =>
                if memory_driver_done = '1' then
                    header_next(i_address * 8 + 7 downto i_address * 8) <= memory_driver_data;

                    if u_address = header'length / 8 - 1 then
                        state_next <= PARSE_HEADER;
                    else
                        memory_driver_start <= '1';
                        memory_driver_addr <= address;

                        address_next <= std_ulogic_vector(u_address + 1);
                    end if;
                end if;

            when PARSE_HEADER => null;
            when FILL_AUDIO_FIFO => null;
        end case;
    end process;
end architecture;
