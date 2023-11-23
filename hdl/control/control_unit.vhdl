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
        memory_driver_address: out std_ulogic_vector(23 downto 0);

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
    type state_t is (
        IDLE, READ_HEADER, PARSE_HEADER, 
        WAIT_FOR_AUDIO_DATA, REQUEST_AUDIO_DATA, 
        WAIT_FOR_VIDEO_DATA, REQUEST_VIDEO_DATA,
        END_OF_FSM
    );
    signal state, state_next: state_t;

    signal address, address_next: std_ulogic_vector(memory_driver_address'range);

    signal header, header_next: std_ulogic_vector(10 * 8 - 1 downto 0);
    alias signature_begin: std_ulogic_vector(7 downto 0) is header(7 downto 0);
    alias signature_end: std_ulogic_vector(7 downto 0) is header(7 + 32 + 32 + 8 downto 32 + 32 + 8);

    signal audio_bytes, video_bytes: unsigned(31 downto 0);

    signal video_base, video_base_next: std_ulogic_vector(31 downto 0);
begin
    audio_bytes <= unsigned(header(31 + 8 downto 8));
    video_bytes <= unsigned(header(31 + 32 + 8 downto 32 + 8));

    audio_driver_start <= '0';

    seq: process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= IDLE;
                address <= (others => '0');
                header <= (others => '0');

                video_base <= (others => '0');
            else
                state <= state_next;
                address <= address_next;
                header <= header_next;

                video_base <= video_base_next;
            end if;
        end if;
    end process;

    fsm: process (state, start, address, header, memory_driver_done, memory_driver_data, audio_fifo_full, video_base, audio_bytes, video_base)
        variable u_address: unsigned(address'range);
    begin
        u_address := unsigned(address);

        state_next <= state;
        address_next <= address;
        header_next <= header;

        memory_driver_start <= '0';
        memory_driver_address <= (others => '0');

        audio_fifo_data_in <= (others => '0');
        audio_fifo_write_enable <= '0';

        video_base_next <= video_base;

        case state is
            when IDLE =>
                if start = '1' then
                    state_next <= READ_HEADER;

                    memory_driver_start <= '1';
                    memory_driver_address <= address;

                    address_next <= std_ulogic_vector(u_address + 1);
                end if;

            when READ_HEADER =>
                if memory_driver_done = '1' then
                    -- Insert from the MSB otherwise the endianness will change.
                    header_next(header'length - 1 downto header'length - memory_driver_data'length) <= memory_driver_data;
                    header_next(header'length - memory_driver_data'length - 1 downto 0) <= header(header'length - 1 downto memory_driver_data'length);

                    -- Since we are reading from IDLE -> READ_HEADER the address was incremented already.
                    -- This means that address contains the next address so we have to check for
                    -- header'length / 8 and not -1.
                    if u_address = header'length / 8 then
                        state_next <= PARSE_HEADER;
                    else
                        memory_driver_start <= '1';
                        memory_driver_address <= address;

                        address_next <= std_ulogic_vector(u_address + 1);
                    end if;
                end if;

            when PARSE_HEADER =>
                if unsigned(signature_begin) = to_unsigned(character'pos('A'), 8)
                    and unsigned(signature_end) = to_unsigned(character'pos('Z'), 8)
                then
                    video_base_next <= std_ulogic_vector(to_unsigned(header'length / 8, video_base_next'length) + audio_bytes);

                    if audio_bytes /= 0 then
                        state_next <= WAIT_FOR_AUDIO_DATA;

                        -- Audio starts immediately after header so we can just continue using address.
                        memory_driver_start <= '1';
                        memory_driver_address <= address;

                        address_next <= std_ulogic_vector(u_address + 1);
                    elsif video_bytes /= 0 then
                        state_next <= WAIT_FOR_VIDEO_DATA;

                        -- Video starts after audio, so we need to add the offset.
                        memory_driver_start <= '1';
                        memory_driver_address <= std_ulogic_vector(u_address + audio_bytes);

                        address_next <= std_ulogic_vector(u_address + audio_bytes + 1);
                    else
                        state_next <= IDLE;
                    end if;
                else
                    report "No media file found in memory." severity failure;
                end if;

            when WAIT_FOR_AUDIO_DATA =>
                if memory_driver_done = '1' then
                    state_next <= REQUEST_AUDIO_DATA;
                end if;

            when REQUEST_AUDIO_DATA =>
                if audio_fifo_full /= '1' then
                    audio_fifo_write_enable <= '1';
                    audio_fifo_data_in <= memory_driver_data;

                    -- We are done reading audio.
                    -- Comparing two different length ulogic vector will yield false
                    -- if they are not equally long even if they are numerically the same.
                    -- Either compare as unsigned or extend to bigger vector.
                    if u_address = unsigned(video_base) then
                        if video_bytes /= 0 then
                            state_next <= WAIT_FOR_VIDEO_DATA;

                            memory_driver_start <= '1';
                            memory_driver_address <= address;

                            address_next <= std_ulogic_vector(u_address + 1);
                        else
                            state_next <= END_OF_FSM;
                        end if;                        
                    else
                        memory_driver_start <= '1';
                        memory_driver_address <= address;

                        address_next <= std_ulogic_vector(u_address + 1);

                        state_next <= WAIT_FOR_AUDIO_DATA;
                    end if;
                else
                    if video_bytes /= 0 then
                        state_next <= WAIT_FOR_VIDEO_DATA;

                        memory_driver_start <= '1';
                        memory_driver_address <= address;

                        address_next <= std_ulogic_vector(u_address + 1);
                    else
                        state_next <= END_OF_FSM;
                    end if;             
                end if;

            when WAIT_FOR_VIDEO_DATA =>
                assert false report "WAIT_FOR_VIDEO_DATA not implemented yet." severity failure;

            when REQUEST_VIDEO_DATA =>
                assert false report "REQUEST_VIDEO_DATA not implemented yet." severity failure;

            when END_OF_FSM =>
                assert false report "END_OF_FSM reached." severity failure;
            
        end case;
    end process;
end architecture;
