const https = require('https');
const { exec } = require('child_process');
const puppeteer = require('puppeteer');
const fs = require('fs');

const urlToCheck = process.env.URL_TO_CHECK;

const options = {
  headers: {
    'User-Agent': 'Mozilla/5.0',
  },
};

function checkHealth(url) {
  return new Promise((resolve, reject) => {
    https.get(url, options, (res) => {
      const statusCode = res.statusCode;
      const failed = statusCode !== 200;
      resolve({ statusCode, failed });
    }).on('error', (err) => {
      resolve({ statusCode: 0, failed: true, error: err.message });
    });
  });
}

async function captureScreenshot(url) {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  await page.goto(url);
  await page.screenshot({ path: 'screenshot.png' });
  await browser.close();
}

async function run() {
  const { statusCode, failed } = await checkHealth(urlToCheck);
  console.log(`URL: ${urlToCheck}`);
  console.log(`Status Code: ${statusCode}`);
  console.log(`Failed: ${failed}`);

  if (failed) {
    console.error(`Health check failed for URL: ${urlToCheck}`);
    console.error(`Status Code: ${statusCode}`);

    await captureScreenshot(urlToCheck);
    
    fs.writeFileSync('STATUS_CODE.txt', statusCode.toString());
    fs.writeFileSync('FAILED_URLS.txt', urlToCheck);
    
    process.exit(1);
  }
}

run();
