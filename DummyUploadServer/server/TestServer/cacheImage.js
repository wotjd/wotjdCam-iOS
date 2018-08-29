/**
 * Created by wotjd on 17. 6. 2.
 */

let cacheImage = {
    'cachedImage' : null,
    'save' : (img) => {
        cacheImage.cachedImage = img;
    },
    'getImage' : () => {
        return cacheImage.cachedImage;
    }
};

export default cacheImage;