use crate::HolosConfig;
use anyhow::Error;
use bzip2::read::BzDecoder;
use cpio::NewcReader;
use log::info;
use std::io::{BufReader, Read};

pub fn do_install(config: &HolosConfig) -> Result<(), Error> {
    Ok(())
}

pub fn old(config: &HolosConfig) -> Result<(), Error> {
    let mut file = std::fs::File::open("/tmp/t.cpio.bz2")?;
    // Create a reader for the raw/compressed file
    let mut reader = BufReader::new(file);

    // Add a reader on top of that to transparently decompress the gzip data
    let mut cpio = Vec::new();
    let mut bz_reader = BzDecoder::new(reader);
    bz_reader.read_to_end(&mut cpio).unwrap();

    loop {
        let cpio_reader = NewcReader::new(&cpio)?;

        if cpio_reader.entry().is_trailer() {
            // We've hit the end of the archive
            break;
        }

        let name = cpio_reader.entry().name();
        info!("File: {}", name);

        //file = cpio_reader.skip()?;
    }

    Ok(())
}
