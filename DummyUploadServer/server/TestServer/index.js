/**
 * Created by wotjd on 17. 5. 22.
 */

import express from 'express'
import bodyParser from 'body-parser'
import routes from './routes'
// import fs from 'fs'

let port = 3000;

let testServer = {
    'app' : null,
    'listen' : () => {
        testServer.app = express();
        // testServer.app.use(bodyParser.json());
        // testServer.app.use('/static', express.static(path.join(__dirname, './../../public')))
        let options = {
            inflate: true,
            limit: '5mb',
            type:'*/*'
        };
        testServer.app.use(bodyParser.raw(options));
        testServer.routes(testServer.app);

        testServer.app.use(function (err, req, res, next) {
            console.error(err.stack);
            res.status(500).send('Something broke!');
        });

        testServer.app.listen(port, () => {
            console.log('test server is listening on port ', port);
        });
    },
    'routes' : (app) => {
        app.use('/', routes);
    }
}

export default testServer;


/*
let app = express();
let port = 3000;

app.set('views', path.join(__dirname, '/../views'));
app.set('view engine', 'ejs');
app.engine('html', require('ejs').renderFile);

let server = app.listen(port, function(){
   console.log("Express server has started on port 3000")
});

app.use(express.static('public'));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({
    extended: true
}));

app.get('/', function(req, res){
    res.render('index.html')
});

app.post("")
*/