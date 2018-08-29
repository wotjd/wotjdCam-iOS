/**
 * Created by wotjd on 17. 5. 22.
 */

import express from 'express'
import path from 'path'
import upload from './upload'
// import cacheImage from './cacheImage'

let router = express.Router();

router.get('/', (req, res) => {
    res.sendFile(path.resolve(__dirname, './../../public/index.html'));
});

router.get('/about', (req, res) => {
    res.sendFile(path.resolve(__dirname, './../../public/about.html'));
});

router.post('/upload', (req, res) => {
    console.log(req.query.av + ":"+ req.query.pts);

    // console.log('[post] /upload : ---- req Header ----\n');
    // console.log(req.headers);
    // console.log('[post] /upload : ---- req body ----\n');
    // console.log(req.body.toString());
    upload.save(req.body, req.query.av, req.query.pts);
    res.send("success");
});
//
// router.get('/getTestImage', (req, res) => {
//     console.log(req.headers);
//     console.log('[get] request from client : image\n');
//     res.sendFile(path.resolve(__dirname, './../../public/Mario.png'));
//     // res.send('\r\n\r\n');
// });
//
// router.post('/sendImage', (req, res) => {
//     console.log('[post] /sendImage : ---- req Header ----\n');
//     console.log(req.headers);
//     console.log('[post] /sendImage : ---- req body ----\n');
//     cacheImage.save(req.body);
//     // console.log(req.body);
//     // console.log(req.body.toString());
//     res.send("success");
// });
//
// router.get('/getImage', (req, res) => {
//     console.log('[get] /getImage\n');
//     let cachedImage = cacheImage.getImage();
//     if (cachedImage != undefined && cachedImage != null) {
//         res.contentType('image/png');
//         res.end(cachedImage, 'binary');
//     }
// });

export default router;