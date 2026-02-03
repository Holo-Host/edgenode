use anyhow::Error;
use aorura::*;
use std::fs::File;
use std::io::BufWriter;

pub struct HoloLed {}

impl HoloLed {
    fn flash_state(flash: bool, color: Color) -> State {
        if flash {
            return State::Flash(color);
        }

        State::Static(color)
    }

    pub fn set_led(flash: bool, color: &str) -> Result<(), Error> {
        let led_state = match color {
            "aurora" => State::Aurora,
            "off" => State::Off,
            "blue" => Self::flash_state(flash, Color::Blue),
            "green" => Self::flash_state(flash, Color::Green),
            "orange" => Self::flash_state(flash, Color::Orange),
            "red" => Self::flash_state(flash, Color::Red),
            "purple" => Self::flash_state(flash, Color::Purple),
            "yellow" => Self::flash_state(flash, Color::Yellow),
            _ => {
                panic!("Unknown LED color: {}", color)
            }
        };

        let file = File::create("/tmp/led")?;
        let writer = BufWriter::new(file);
        serde_yaml::to_writer(writer, &led_state)?;

        let mut led = Led::open("/dev/ttyUSB0").unwrap();
        led.set(led_state).unwrap();
        Ok(())
    }
}
