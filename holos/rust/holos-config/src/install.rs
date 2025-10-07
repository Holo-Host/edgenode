use crate::HolosConfig;
use anyhow::Error;
use cpio::NewcReader;
use flate2::read::GzDecoder;
use log::info;
use std::io::BufReader;

pub fn do_install(config: &HolosConfig) -> Result<(), Error> {
    Ok(())
}

pub fn old(config: &HolosConfig) -> Result<(), Error> {
    //dbg!(config);
    let mut file = std::fs::File::open("/tmp/t.cpio.gz")?;
    // Create a reader for the raw/compressed file
    let mut reader = BufReader::new(file);

    // Add a reader on top of that to transparently decompress the gzip data
    let mut gz_reader = GzDecoder::new(reader);

    /*
    loop {
        let cpio_reader = NewcReader::new(gz_reader)?;

        if cpio_reader.entry().is_trailer() {
            // We've hit the end of the archive
            break;
        }

        let name = cpio_reader.entry().name();
        info!("File: {}", name);

        //file = cpio_reader.skip()?;
    }*/

    Ok(())
}
