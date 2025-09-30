/// This module uses some basic/crude heuristics to try and determine the model of machine we're
/// running on, to provide a potential default configuration file.
pub struct ModelConfig {}

impl ModelConfig {
    pub fn config_file() -> Option<String> {
        Some("/etc/holos/configs/default.yaml".to_string())
    }
}
