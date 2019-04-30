
#include <base/attached_rom_dataspace.h>
#include <util/reconstructible.h>
#include <util/xml_node.h>
#include <configuration_client.h>
#include <factory.h>

static Genode::Constructible<Factory> _factory;

class Config
{
    private:
        Genode::Attached_rom_dataspace _ds;
        Genode::Signal_handler<Config> _sigh;

        void (*_parse)(void const *, Genode::uint64_t);
        static char const _empty;

    public:
        Config(Genode::Env &, void (*)(void const *, Genode::uint64_t));
        void update();
};

char const Config::_empty = '\0';

Config::Config(Genode::Env &env, void (*parse)(void const *, Genode::uint64_t)) :
    _ds(env, "config"),
    _sigh(env.ep(), *this, &Config::update),
    _parse(parse)
{
    _ds.sigh(_sigh);
    _ds.update();
}

void Config::update()
{
    _ds.update();
    try{
        Genode::Xml_node raw = _ds.xml().sub_node();
        _parse(static_cast<void const *>(raw.content_base()), raw.content_size());
    }catch(...){
        _parse(static_cast<void const *>(&_empty), 0);
    }
}

Cai::Configuration::Client::Client() :
    _config(nullptr)
{ }

void Cai::Configuration::Client::initialize(void *env, void *parse)
{
    check_factory(_factory, *reinterpret_cast<Genode::Env *>(env));
    _config = _factory->create<Config>(*reinterpret_cast<Genode::Env *>(env),
                                       reinterpret_cast<void (*)(void const *, Genode::uint64_t)>(parse));
}

bool Cai::Configuration::Client::initialized()
{
    return _config;
}

void Cai::Configuration::Client::load()
{
    reinterpret_cast<Config *>(_config)->update();
}

void Cai::Configuration::Client::finalize()
{
    _factory->destroy<Config>(_config);
    _config = nullptr;
}