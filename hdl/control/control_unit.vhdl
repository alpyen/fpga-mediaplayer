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
        WAIT_FOR_DATA, REQUEST_DATA, WAIT_FOR_EMPTY_SLOT,
        DONE
    );
    signal state, state_next: state_t;

    signal header, header_next: std_ulogic_vector(10 * 8 - 1 downto 0);
    alias signature_begin: std_ulogic_vector(7 downto 0) is header(7 downto 0);
    alias audio_length: std_ulogic_vector(memory_driver_address'range) is header(8 + memory_driver_address'length - 1 downto 8);
    alias video_length: std_ulogic_vector(memory_driver_address'range) is header(8 + 32 + memory_driver_address'length - 1 downto 8 + 32);
    alias signature_end: std_ulogic_vector(7 downto 0) is header(7 + 32 + 32 + 8 downto 32 + 32 + 8);

    signal audio_pointer, audio_pointer_next: std_ulogic_vector(memory_driver_address'range);
    signal audio_end_address, audio_end_address_next: std_ulogic_vector(memory_driver_address'range);

    signal video_pointer, video_pointer_next: std_ulogic_vector(memory_driver_address'range);
    signal video_end_address, video_end_address_next: std_ulogic_vector(memory_driver_address'range);

    -- If this signal is zero, read and wait for audio, if it's one, read and wait for video.
    signal read_audio_n_video, read_audio_n_video_next: std_ulogic;

    signal start_playback, start_playback_next: std_ulogic;

    -- TODO: Remove when Video Fifo is attached
    signal video_driver_start: std_ulogic;
    signal video_fifo_write_enable: std_ulogic;
    signal video_fifo_data_in: std_ulogic_vector(7 downto 0);
    signal video_fifo_full: std_ulogic := '1';
begin
    seq: process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                state <= IDLE;

                header <= (others => '0');

                audio_pointer <= (others => '0');
                audio_end_address <= (others => '0');

                video_pointer <= (others => '0');
                video_end_address <= (others => '0');

                read_audio_n_video <= '0';

                start_playback <= '0';
            else
                state <= state_next;

                header <= header_next;

                audio_pointer <= audio_pointer_next;
                audio_end_address <= audio_end_address_next;

                video_pointer <= video_pointer_next;
                video_end_address <= video_end_address_next;

                read_audio_n_video <= read_audio_n_video_next;

                start_playback <= start_playback_next;
            end if;
        end if;
    end process;

    fsm: process (
        state, start,
        header, memory_driver_done, memory_driver_data,
        audio_fifo_full, audio_pointer, audio_end_address,
        video_fifo_full, video_pointer, video_end_address,
        read_audio_n_video, start_playback
    )
        variable u_audio_pointer, u_video_pointer: unsigned(audio_pointer'range);
        variable u_audio_length, u_video_length: unsigned(audio_length'range);
    begin
        u_audio_pointer := unsigned(audio_pointer);
        u_video_pointer := unsigned(video_pointer);

        u_audio_length := unsigned(audio_length);
        u_video_length := unsigned(video_length);

        state_next <= state;

        header_next <= header;

        audio_fifo_data_in <= (others => '0');
        audio_fifo_write_enable <= '0';

        audio_pointer_next <= audio_pointer;
        audio_end_address_next <= audio_end_address;

        video_fifo_data_in <= (others => '0');
        video_fifo_write_enable <= '0';

        video_pointer_next <= video_pointer;
        video_end_address_next <= video_end_address;

        read_audio_n_video_next <= read_audio_n_video;

        memory_driver_start <= '0';
        memory_driver_address <= (others => '0');

        start_playback_next <= start_playback;

        audio_driver_start <= '0';
        video_driver_start <= '0';

        case state is
            when IDLE =>
                if start = '1' then
                    state_next <= READ_HEADER;

                    -- We are reading the header first, not the audio but instead of spending
                    -- more hardware to have designated flipflops to hold the current address
                    -- of the header, we can simply use the audio pointer.
                    -- This also has the neat effect, that it lands on the first audio byte
                    -- if audio was included!
                    memory_driver_start <= '1';
                    memory_driver_address <= audio_pointer;

                    audio_pointer_next <= std_ulogic_vector(u_audio_pointer + 1);
                end if;

            when READ_HEADER =>
                if memory_driver_done = '1' then
                    -- Insert from the MSB otherwise the endianness will change.
                    header_next(header'length - 1 downto header'length - memory_driver_data'length) <= memory_driver_data;
                    header_next(header'length - memory_driver_data'length - 1 downto 0) <= header(header'length - 1 downto memory_driver_data'length);

                    -- Since we are reading from IDLE -> READ_HEADER the address was incremented already.
                    -- This means that address contains the next address so we have to check for
                    -- header'length / 8 and not -1.
                    if u_audio_pointer = header'length / 8 then
                        state_next <= PARSE_HEADER;
                    else
                        memory_driver_start <= '1';
                        memory_driver_address <= audio_pointer;

                        audio_pointer_next <= std_ulogic_vector(u_audio_pointer + 1);
                    end if;
                end if;

            when PARSE_HEADER =>
                if unsigned(signature_begin) = to_unsigned(character'pos('A'), 8)
                    and unsigned(signature_end) = to_unsigned(character'pos('Z'), 8)
                then
                    audio_end_address_next <= std_ulogic_vector(u_audio_pointer + u_audio_length);
                    video_end_address_next <= std_ulogic_vector(u_video_pointer + u_video_length);

                    if u_audio_length /= 0 then
                        state_next <= WAIT_FOR_DATA;
                        read_audio_n_video_next <= '0';

                        memory_driver_start <= '1';
                        memory_driver_address <= audio_pointer;

                        audio_pointer_next <= std_ulogic_vector(u_audio_pointer + 1);
                    elsif u_video_length /= 0 then
                        state_next <= WAIT_FOR_DATA;
                        read_audio_n_video_next <= '1';

                        -- audio_length / video_length are only valid in PARSE_HEADER that's why we need to
                        -- calculate the address here, otherwise we would have read it from video_pointer directly.

                        memory_driver_start <= '1';
                        memory_driver_address <= std_ulogic_vector(u_audio_pointer + u_audio_length);

                        video_pointer_next <= std_ulogic_vector(u_audio_pointer + u_audio_length + 1);
                    else
                        state_next <= IDLE;

                        -- Reset the audio pointer since that is used to parse the header.
                        audio_pointer_next <= (others => '0');
                    end if;
                else
                    report "No media file found in memory." severity failure;
                end if;

            when WAIT_FOR_DATA =>
                if memory_driver_done = '1' then
                    state_next <= REQUEST_DATA;

                    read_audio_n_video_next <= not read_audio_n_video;

                    if read_audio_n_video = '0' then
                        audio_fifo_write_enable <= '1';
                        audio_fifo_data_in <= memory_driver_data;
                    else
                        video_fifo_write_enable <= '1';
                        video_fifo_data_in <= memory_driver_data;
                    end if;
                end if;

            when REQUEST_DATA =>
                if audio_pointer = audio_end_address and video_pointer = video_end_address then
                    state_next <= DONE;

                    -- We have to start playback if the audio and video data completely fit inside
                    -- the Fifos before hitting WAIT_FOR_EMPTY_SLOT.
                    if start_playback = '0' then
                        start_playback_next <= '1';

                        audio_driver_start <= '1';
                        video_driver_start <= '1';
                    end if;

                    audio_pointer_next <= (others => '0');
                elsif read_audio_n_video = '0' then
                    if audio_fifo_full = '0' then
                        -- We are done reading audio.
                        -- Comparing two different length ulogic vector will yield false
                        -- if they are not equally long even if they are numerically the same.
                        -- Either compare as unsigned or extend to bigger vector.
                        if u_audio_pointer = unsigned(audio_end_address) then
                            read_audio_n_video_next <= '1';
                        else
                            memory_driver_start <= '1';
                            memory_driver_address <= audio_pointer;

                            audio_pointer_next <= std_ulogic_vector(u_audio_pointer + 1);
                            state_next <= WAIT_FOR_DATA;
                        end if;
                    else
                        if video_fifo_full = '0' then
                            read_audio_n_video_next <= '1';
                        else
                            read_audio_n_video_next <= '1';
                            state_next <= WAIT_FOR_EMPTY_SLOT;
                        end if;
                    end if;
                else
                    if video_fifo_full = '0' then
                        if u_video_pointer = unsigned(video_end_address) then
                            read_audio_n_video_next <= '0';
                        else
                            memory_driver_start <= '1';
                            memory_driver_address <= video_pointer;

                            video_pointer_next <= std_ulogic_vector(u_video_pointer + 1);
                            state_next <= WAIT_FOR_DATA;
                        end if;
                    else
                        if audio_fifo_full = '0' then
                            read_audio_n_video_next <= '0';
                        else
                            read_audio_n_video_next <= '0';
                            state_next <= WAIT_FOR_EMPTY_SLOT;
                        end if;
                    end if;
                end if;

            when WAIT_FOR_EMPTY_SLOT =>
                if start_playback = '0' then
                    start_playback_next <= '1';

                    audio_driver_start <= '1';
                    video_driver_start <= '1';
                end if;

                if audio_fifo_full = '0' then
                    state_next <= REQUEST_DATA;
                    read_audio_n_video_next <= '0';
                elsif video_fifo_full = '0' then
                    state_next <= REQUEST_DATA;
                    read_audio_n_video_next <= '1';
                end if;

            when DONE =>
                null;
        end case;
    end process;
end architecture;
