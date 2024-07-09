import {Logger} from "../utils/logger";
import {IStream, IVideoProvider} from "./backend";
import {BasePlugin} from "../utils/plugin";
import {CachingFactory, ICacheable} from "../utils/cache";

export class UnifiVideoProvider extends BasePlugin implements IVideoProvider {
    _logger = Logger.createLogger(UnifiVideoProvider.name);
    private _unifiNvrFactory = new CachingFactory<UnifiNVR>(
        UnifiNVR,
        (...args: any[]) => `${args[0]}:${args[1]}`);

    constructor() {
        super('unifi');
    }

    /**
     * Handles URLs in the form of unifi://.../camera/...
     */
    public canHandle(url: URL): boolean {
        if(url.protocol.split(':')[0] == 'unifi' &&
            decodeURI(url.pathname).split('/')[1] == 'camera') {
            return true;
        } else {
            return false;
        }
    }

    public async getOrCreateStreams(url: URL): Promise<IStream[]> {
        let splitPathname = decodeURI(url.pathname).split('/');
        if(splitPathname[2].trim().length == 0) {
            throw new Error(`Expecting url.pathname to specify either '/camera/_all' or /camera/camera1,camera2... but got '${splitPathname[2]}'`);
        }

        this._logger.debug(`Getting or creating the UnifiNVR for url '${url}'`);
        let unifiNvr = await this._unifiNvrFactory.getOrCreate(
            url.host,
            url.username,
            url.password);

        this._logger.debug(`Processing requested cameras`);

        const cameras = [];
        const requestedCameras = splitPathname[2];
        this._logger.debug(`Requested cameras: '${requestedCameras}'`);

        if(requestedCameras == '_all') {
            for(let camera of unifiNvr.cameras) {
                cameras.push({
                    id: camera.id,
                    name: camera.name
                });
            }
        } else {
            const requestedCamerasList: string[] = requestedCameras.split(',').map(val => val.trim());
            for(let requestedCamera of requestedCamerasList) {
                let camera = unifiNvr.cameras.filter((val) => requestedCameras == val.name);
                if(camera.length == 1) {
                    cameras.push({
                        id: camera[0].id,
                        name: camera[0].name
                    });
                } else {
                    this._logger.error(`Cannot find camera named '${requestedCamera}' in UnifiNVR at '${unifiNvr.host}'`);
                    throw new Error(`Camera '${requestedCamera}' not found`);
                }
            }
        }

        this._logger.debug(`Found '${cameras.length}' cameras: '${cameras.map((val) => val.name)}'`);
        this._logger.info(`Creating '${cameras.length}' transcoders`);
        process.exit(0);

    }
}

export class UnifiStream implements IStream {
    private _logger = Logger.createLogger(UnifiStream.name);
    private readonly _url;
    private readonly _id: string;
    private _codec: string;
    private _container: string;
    private _endpoint: string;

    constructor(url: URL) {
        this._url = url;
        this._id = this._url;
    }

    public get id(): string { return this._id; }
    public get codec(): string { return this._codec; }
    public get container(): string { return this._container }
    public get endpoint(): string { return this._endpoint }

    public start() {
        this._logger.debug(`Starting stream '${this.id}'...`);
        //this._logger.debug(`Connecting to Unifi fMPEG web socket for camera ${this._camera.name }`);
    }

    public stop() {
        this._logger.debug(`Stopping stream '${this.id}'`);
    }
}

class UnifiNVR implements ICacheable {
    private _logger = Logger.createLogger(UnifiNVR.name);
    private _host;
    private _username;
    private _password;
    private _protectApi;

    static _unifiProtectModule;

    public async initialize(host, username, password): Promise<void> {
        this._logger.debug(`Initializing new ${UnifiNVR.name} instance`);

        this._host = host;
        this._username = username;
        this._password = password;

        // TODO Fix this Jest-induced kludge
        if(UnifiNVR._unifiProtectModule == undefined) {
            UnifiNVR._unifiProtectModule = await import('unifi-protect');
        }
        this._protectApi = new UnifiNVR._unifiProtectModule.ProtectApi();

        this._logger.info(`Connecting to NVR at '${this._host}' with username '${this._username}'...`)
        if(!(await this._protectApi.login(this._host, this._username, this._password))) {
            throw new Error('Invalid login credentials');
        };

        if(!(await this._protectApi.getBootstrap())) {
            throw new Error("Unable to bootstrap the Protect controller");
        }

        this._logger.info('Connected successfully');
    }

    public get host() { return this._host; };
    public get cameras() { return this._protectApi.bootstrap.cameras; };

    public addListener(cameraId, listener) {
        let protectLiveStream = this._protectApi.createLivestream();
        protectLiveStream.addListener('codec', (codec) => this._logger.info(codec));
        protectLiveStream.addListener('message', listener);
        protectLiveStream.start(cameraId, 0);

    }

    public removeListener(listener) {

    }
}