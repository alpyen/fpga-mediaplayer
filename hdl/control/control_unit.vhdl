library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity control_unit is
    generic (
        WIDTH: positive;
        HEIGHT: positive
    );
    port (
        clock: in std_ulogic;
        reset: in std_ulogic;

        start: in std_ulogic;

        media_base_address: in std_ulogic_vector(23 downto 0);

        -- Memory Driver Interface
        memory_driver_start: out std_ulogic;
        memory_driver_address: out std_ulogic_vector(23 downto 0);

        memory_driver_data: in std_ulogic_vector(7 downto 0);
        memory_driver_done: in std_ulogic;

        -- Audio Driver Interface
        audio_driver_play: out std_ulogic;
        audio_driver_done: in std_ulogic;

        -- Audio Fifo
        audio_fifo_write_enable: out std_ulogic;
        audio_fifo_data_in: out std_ulogic_vector(7 downto 0);
        audio_fifo_full: in std_ulogic;

        -- Video Driver Interface
        video_driver_play: out std_ulogic;
        video_driver_done: in std_ulogic;

        -- Video Fifo
        video_fifo_write_enable: out std_ulogic;
        video_fifo_data_in: out std_ulogic_vector(7 downto 0);
        video_fifo_full: in std_ulogic
    );
end entity;

architecture arch of control_unit is
    type state_t is (
        IDLE, READ_HEADER, PRELOAD_DATA, PARSE_HEADER,
        WAIT_FOR_DATA, REQUEST_DATA, WAIT_FOR_DONE
    );
    signal state, state_next: state_t;

    signal header, header_next: std_ulogic_vector(12 * 8 - 1 downto 0);
    alias signature_begin: std_ulogic_vector(7 downto 0) is header(7 downto 0);
    alias video_width: std_ulogic_vector(7 downto 0) is header(7 + 8 downto 8);
    alias video_height: std_ulogic_vector(7 downto 0) is header(7 + 8 + 8 downto 8 + 8);
    alias audio_length: std_ulogic_vector(memory_driver_address'range) is header(8 + 2*8 + memory_driver_address'length - 1 downto 2*8 + 8);
    alias video_length: std_ulogic_vector(memory_driver_address'range) is header(8 + 2*8 + 32 + memory_driver_address'length - 1 downto 2*8 + 8 + 32);
    alias signature_end: std_ulogic_vector(7 downto 0) is header(7 + 2*8 + 2*32 + 8 downto 2*8 + 2*32 + 8);

    signal audio_pointer, audio_pointer_next: std_ulogic_vector(memory_driver_address'range);
    signal audio_end_address, audio_end_address_next: std_ulogic_vector(memory_driver_address'range);

    signal video_pointer, video_pointer_next: std_ulogic_vector(memory_driver_address'range);
    signal video_end_address, video_end_address_next: std_ulogic_vector(memory_driver_address'range);

    -- If this signal is '1', read and wait for audio, if it's '0', read and wait for video.
    signal read_audio_n_video, read_audio_n_video_next: std_ulogic;

    -- If true, there is data still to be loaded into the Fifos, if not, then not.
    signal play, play_next: std_ulogic;

    signal preloading, preloading_next: std_ulogic;
begin
    audio_driver_play <= play;
    video_driver_play <= play;

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

                read_audio_n_video <= '1';

                preloading <= '0';
                play <= '0';
            else
                state <= state_next;

                header <= header_next;

                audio_pointer <= audio_pointer_next;
                audio_end_address <= audio_end_address_next;

                video_pointer <= video_pointer_next;
                video_end_address <= video_end_address_next;

                read_audio_n_video <= read_audio_n_video_next;

                preloading <= preloading_next;
                play <= play_next;
            end if;
        end if;
    end process;

    fsm: process (
        state, start, media_base_address,
        header, memory_driver_done, memory_driver_data,
        audio_fifo_full, audio_pointer, audio_end_address,
        video_fifo_full, video_pointer, video_end_address,
        read_audio_n_video,
        audio_driver_done, video_driver_done,
        play, preloading
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

        play_next <= play;
        preloading_next <= preloading;

        case state is
            when IDLE =>
                if start = '1' then
                    state_next <= READ_HEADER;

                    memory_driver_start <= '1';
                    memory_driver_address <= media_base_address;

                    audio_pointer_next <= std_ulogic_vector(unsigned(media_base_address) + 1);
                end if;

            when READ_HEADER =>
                if memory_driver_done = '1' then
                    -- Insert from the MSB otherwise the endianness will change.
                    header_next(header'length - 1 downto header'length - memory_driver_data'length) <= memory_driver_data;
                    header_next(header'length - memory_driver_data'length - 1 downto 0) <= header(header'length - 1 downto memory_driver_data'length);

                    -- Since we are reading from IDLE -> READ_HEADER the address was incremented already.
                    -- This means that address contains the next address so we have to check for
                    -- header'length / 8 and not -1.
                    if u_audio_pointer = unsigned(media_base_address) + header'length / 8 then
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
                    and unsigned(video_width) <= WIDTH
                    and unsigned(video_height) <= HEIGHT
                then
                    audio_end_address_next <= std_ulogic_vector(u_audio_pointer + u_audio_length);
                    video_end_address_next <= std_ulogic_vector(u_audio_pointer + u_audio_length + u_video_length);

                    audio_pointer_next <= std_ulogic_vector(u_audio_pointer);
                    video_pointer_next <= std_ulogic_vector(u_audio_pointer + u_audio_length);

                    if u_audio_length /= 0 or u_video_length /= 0 then
                        state_next <= PRELOAD_DATA;

                        read_audio_n_video_next <= '1';
                        preloading_next <= '1';
                    else
                        report "Media file contains neither audio nor video.";
                        state_next <= IDLE;
                    end if;
                else
                    state_next <= IDLE;
                    report "No media file found in memory or its resolution is too big for the instantiated module." severity failure;
                end if;

            when PRELOAD_DATA =>
                if read_audio_n_video = '1' then
                    -- Preloading for audio is done when we are at the end address
                    -- or the audio fifo can hold all samples, otherwise keep loading.
                    if audio_pointer = audio_end_address or audio_fifo_full = '1' then
                        read_audio_n_video_next <= '0';
                    else
                        state_next <= WAIT_FOR_DATA;
                        memory_driver_start <= '1';
                        memory_driver_address <= audio_pointer;
                        audio_pointer_next <= std_ulogic_vector(u_audio_pointer + 1);
                    end if;
                else
                    if video_pointer = video_end_address or video_fifo_full = '1' then
                        read_audio_n_video_next <= '1';

                        -- We could also hop to WAIT_FOR_DATA, doesn't really matter.
                        state_next <= REQUEST_DATA;
                        preloading_next <= '0';

                        -- We are ready to play!
                        play_next <= '1';
                    else
                        state_next <= WAIT_FOR_DATA;
                        memory_driver_start <= '1';
                        memory_driver_address <= video_pointer;
                        video_pointer_next <= std_ulogic_vector(u_video_pointer + 1);
                    end if;
                end if;

            when WAIT_FOR_DATA =>
                if memory_driver_done = '1' then
                    if read_audio_n_video = '1' then
                        audio_fifo_write_enable <= '1';

                        -- Reverse the bit order going into the Fifo because
                        -- the output is only one bit and it outputs MSB first.
                        audio_fifo_data_in <=
                            memory_driver_data(0) &
                            memory_driver_data(1) &
                            memory_driver_data(2) &
                            memory_driver_data(3) &
                            memory_driver_data(4) &
                            memory_driver_data(5) &
                            memory_driver_data(6) &
                            memory_driver_data(7)
                        ;

                        if preloading = '1' then
                            state_next <= PRELOAD_DATA;
                        else
                            state_next <= REQUEST_DATA;
                            -- If we are not preloading we want to fill both buffers
                            -- alternatingly instead of one and then the other.
                            read_audio_n_video_next <= not read_audio_n_video;
                        end if;
                    else
                        video_fifo_write_enable <= '1';

                        video_fifo_data_in <=
                            memory_driver_data(0) &
                            memory_driver_data(1) &
                            memory_driver_data(2) &
                            memory_driver_data(3) &
                            memory_driver_data(4) &
                            memory_driver_data(5) &
                            memory_driver_data(6) &
                            memory_driver_data(7)
                        ;

                        if preloading = '1' then
                            state_next <= PRELOAD_DATA;
                        else
                            state_next <= REQUEST_DATA;
                            read_audio_n_video_next <= not read_audio_n_video;
                        end if;
                    end if;
                end if;

            when REQUEST_DATA =>
                if audio_pointer = audio_end_address and video_pointer = video_end_address then
                    state_next <= WAIT_FOR_DONE;
                    play_next <= '0';
                else
                    if read_audio_n_video = '1' then
                        -- If we are not at the end of the data and the fifo is not full
                        -- then we can insert new data into the fifo.
                        -- Otherwise we will just switch to reading video.
                        -- This is a bit wasteful as we are switching back and forth if no slot is available
                        -- or no data is available but it's easier this way than to clutter the code
                        -- to catch all possibilities (also it makes no speed difference).
                        if audio_pointer /= audio_end_address and audio_fifo_full /= '1' then
                            state_next <= WAIT_FOR_DATA;
                            memory_driver_start <= '1';
                            memory_driver_address <= audio_pointer;
                            audio_pointer_next <= std_ulogic_vector(u_audio_pointer + 1);
                        else
                            read_audio_n_video_next <= not read_audio_n_video;
                        end if;
                    else
                        if video_pointer /= video_end_address and video_fifo_full /= '1' then
                            state_next <= WAIT_FOR_DATA;
                            memory_driver_start <= '1';
                            memory_driver_address <= video_pointer;
                            video_pointer_next <= std_ulogic_vector(u_video_pointer + 1);
                        else
                            read_audio_n_video_next <= not read_audio_n_video;
                        end if;
                    end if;
                end if;

            when WAIT_FOR_DONE =>
                if audio_driver_done = '1' and video_driver_done = '1' then
                    state_next <= IDLE;
                end if;
        end case;
    end process;
end architecture;
