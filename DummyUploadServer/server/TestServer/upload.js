'use strict';

import fs from 'fs'

Object.defineProperty(exports, "__esModule", {
    value: true
});
/**
 * Created by wotjd on 17. 6. 2.
 */

var upload = {
    'upload': function(data, type, name) {
        save(data, type, name)
    },
    'save': function(data, type, name) {
        // console.log("saving " + type + "....")
        // console.log(data)
        if (type == "video") {
            fs.writeFile("output/" + type + "/" + name + ".h264", data, 'utf-8');
        } else if (type == "audio") {
            fs.writeFile("output/" + type + "/" + name + ".aac", data, 'utf-8');
        }
    }
};



exports.default = upload;