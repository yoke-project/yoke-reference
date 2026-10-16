#include "picture.hpp"

#include <algorithm>
#include <sstream>

namespace panel {

std::string key(const v1::Record &record) {
    switch (record.subject_case()) {
    case v1::Record::kInstance:
        return "instance";
    case v1::Record::kChannel:
        return "channel/" + record.channel().declared().name();
    case v1::Record::kUnit:
        return "unit/" + record.unit().declared().identity();
    default:
        return "";
    }
}

Picture::Picture(const v1::Snapshot &opening) { replace(opening); }

void Picture::replace(const v1::Snapshot &snapshot) {
    records_.assign(snapshot.records().begin(), snapshot.records().end());
    at_ = applied_ = snapshot.at();
    behind_ = false;
}

void Picture::put(const v1::Record &record) {
    std::string k = key(record);
    auto it = std::find_if(records_.begin(), records_.end(), [&](const v1::Record &r) { return key(r) == k; });
    if (it != records_.end()) {
        *it = record;
    } else {
        records_.push_back(record);
    }
}

const v1::InstanceRecord *Picture::instance() const {
    for (const auto &r : records_) {
        if (r.has_instance()) {
            return &r.instance();
        }
    }
    return nullptr;
}

const v1::ChannelRecord *Picture::channel() const {
    for (const auto &r : records_) {
        if (r.has_channel()) {
            return &r.channel();
        }
    }
    return nullptr;
}

std::vector<const v1::UnitRecord *> Picture::units() const {
    std::vector<const v1::UnitRecord *> out;
    for (const auto &r : records_) {
        if (r.has_unit()) {
            out.push_back(&r.unit());
        }
    }
    return out;
}

bool Picture::apply(const v1::Subscribed &delivery, const Reader &read) {
    if (delivery.has_overflow() || delivery.has_snapshot()) {
        replace(delivery.has_overflow() ? delivery.overflow() : delivery.snapshot());
        return true;
    }
    if (!delivery.has_event()) {
        return false;
    }
    const v1::Event &e = delivery.event();
    const std::string kind = e.subject().kind(), identity = e.subject().identity();
    if (kind != "instance" && kind != "unit" && kind != "channel") {
        // A subject the picture holds no record of changes nothing it shows.
        if (!behind_) {
            applied_ = e.seq();
        }
        return false;
    }
    std::vector<v1::Record> fresh;
    try {
        fresh = read(kind, kind == "unit" ? identity : "");
    } catch (...) {
        behind_ = true;
        return false;
    }
    if (kind == "unit" && fresh.empty()) {
        // The unit is no longer one the channel sees.
        records_.erase(std::remove_if(records_.begin(), records_.end(),
                                      [&](const v1::Record &r) { return key(r) == "unit/" + identity; }),
                       records_.end());
    }
    for (const auto &r : fresh) {
        put(r);
    }
    if (!behind_) {
        applied_ = e.seq();
    }
    return true;
}

std::string summary(const Picture &picture) {
    std::ostringstream out;
    auto list = [&](const char *name, const auto &items) {
        out << " " << name << "=[";
        for (int i = 0; i < items.size(); i++) {
            out << (i ? "," : "") << items[i];
        }
        out << "]";
    };
    for (const auto *u : picture.units()) {
        out << "composed: unit " << u->declared().identity() << " "
            << (u->observed().state().empty() ? "unknown" : u->observed().state());
        list("commands", u->addressed().commands());
        list("queries", u->addressed().queries());
        list("streams", u->addressed().streams());
        out << "\n";
    }
    return out.str();
}

} // namespace panel
