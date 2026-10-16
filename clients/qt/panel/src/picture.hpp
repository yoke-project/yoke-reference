// The panel's picture: what the channel presents, held by subject, and kept current from the standing
// subscription. It knows no unit, no Plugin and no domain, and nothing of Qt.
#ifndef PANEL_PICTURE_HPP
#define PANEL_PICTURE_HPP

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include <yoke/interface.hpp>

namespace panel {

namespace v1 = yoke::iface::v1;

// The subject a record is about, as the key the picture holds it by.
std::string key(const v1::Record &record);

class Picture {
  public:
    // Reads the records of a kind, or of the one unit an identity names; throws when it cannot.
    using Reader = std::function<std::vector<v1::Record>(const std::string &kind, const std::string &identity)>;

    explicit Picture(const v1::Snapshot &opening);

    // The sequence the picture was taken at, and the one it is current to: what may be confirmed.
    std::uint64_t at() const { return at_; }
    std::uint64_t applied() const { return applied_; }

    const std::vector<v1::Record> &records() const { return records_; }
    const v1::InstanceRecord *instance() const;
    const v1::ChannelRecord *channel() const;
    std::vector<const v1::UnitRecord *> units() const;

    // Applies one delivery of the standing subscription. An event's subject is read again and replaces
    // what the picture held; a subject that cannot be read leaves the picture behind, and nothing past it
    // is applied until an overflow replaces the picture whole. Whether the picture changed.
    bool apply(const v1::Subscribed &delivery, const Reader &read);

  private:
    void put(const v1::Record &record);
    void replace(const v1::Snapshot &snapshot);

    std::vector<v1::Record> records_;
    std::uint64_t at_ = 0, applied_ = 0;
    bool behind_ = false;
};

// One line per unit, saying what the panel composed for it: its state and what it may be asked.
std::string summary(const Picture &picture);

} // namespace panel

#endif
