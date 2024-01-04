use std::io::BufRead;
use std::iter::repeat_with;
use std::sync::mpsc::sync_channel;
use std::time::Instant;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (url_producer_handle, rx_urls) = {
        let (mut tx_urls, rx_urls) = spmc::channel();
        let file = std::fs::File::open("urls.txt")?;
        let buffile = std::io::BufReader::new(file);
        let handle = tokio::spawn(async move {
            for line in buffile.lines() {
                let line = line.unwrap();
                tx_urls.send(line).unwrap();
            }
        });
        (handle, rx_urls)
    };

    let (worker_handles, rx_results): (Vec<_>, _) = {
        let workers = 1000;
        let (tx_results, rx_results) = sync_channel(workers);
        let client = reqwest::Client::new();
        let create_worker = move || {
            let client = client.clone();
            let rx = rx_urls.clone();
            let tx = tx_results.clone();
            tokio::spawn(async move {
                while let Ok(line) = rx.recv() {
                    let start = Instant::now();
                    let resp = client.get(&line).send().await;
                    let duration = start.elapsed();
                    let item = resp.map(|r| r.status().as_u16());
                    tx.send((line, item, duration)).unwrap();
                }
            })
        };
        (
            repeat_with(create_worker).take(workers).collect(),
            rx_results,
        )
    };

    let result_handle = tokio::spawn(async move {
        while let Ok((url, maybe_result, duration)) = rx_results.recv() {
            let (code, error) = match maybe_result {
                Ok(result) => (result.to_string(), String::new()),
                Err(x) => (String::new(), x.to_string()),
            };
            println!("{},{},{:?},{}", url, code, duration, error);
        }
    });

    url_producer_handle.await?;
    for handle in worker_handles {
        handle.await?;
    }
    result_handle.await?;

    Ok(())
}
