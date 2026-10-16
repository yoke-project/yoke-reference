// The panel, as the Core launches it: it attaches to the channel it is handed, composes its window from
// the opening, and keeps it current from the standing subscription. `--socket <path>` attaches to a
// channel by hand instead.
#include <atomic>
#include <cstdlib>
#include <iostream>
#include <map>
#include <mutex>
#include <thread>

#include <QApplication>
#include <QMetaObject>

#include "picture.hpp"
#include "window.hpp"

namespace yi = yoke::iface;

namespace {

// What the window asks, done on the attachment.
class Attached : public panel::Acts {
  public:
    explicit Attached(yi::Attachment &a) : a_(a) {}

    std::string command(const std::string &unit, const std::string &type, const std::string &payload) override {
        auto ack = a_.command(unit, type, payload);
        std::string outcome = yi::v1::Acknowledged::Outcome_Name(ack.outcome());
        return outcome + (ack.line().empty() ? "" : ": " + ack.line());
    }
    std::string ask(const std::string &unit, const std::string &type, const std::string &payload) override {
        return a_.ask(unit, type, payload);
    }
    std::string start(const std::string &unit, const std::string &stream) override {
        return yi::v1::Acknowledged::Outcome_Name(a_.start_stream(unit, stream).outcome());
    }
    std::string stop(const std::string &unit, const std::string &stream) override {
        return yi::v1::Acknowledged::Outcome_Name(a_.stop_stream(unit, stream).outcome());
    }
    std::string watch(const std::string &unit, const std::string &stream,
                      std::function<void(const std::string &)> told) override {
        std::lock_guard<std::mutex> hold(mu_);
        const std::string key = unit + "/" + stream;
        if (auto it = watching_.find(key); it != watching_.end()) {
            it->second->release();
            watching_.erase(it);
            return "released";
        }
        std::shared_ptr<yi::Delivery> d = a_.subscribe_stream(unit, stream);
        watching_[key] = d;
        std::thread([d, told] {
            std::uint64_t frames = 0;
            try {
                while (auto f = d->next()) {
                    told("#" + std::to_string(f->sequence) + " · " + std::to_string(f->payload.size()) + " bytes · " +
                         std::to_string(++frames) + " received");
                }
            } catch (...) {
            }
        }).detach();
        return d->flowing() ? "watching" : "watching — not flowing yet";
    }
    std::string reclaim() override { return a_.reclaim().changed() ? "reclaimed" : "nothing to reclaim"; }

  private:
    yi::Attachment &a_;
    std::mutex mu_;
    std::map<std::string, std::shared_ptr<yi::Delivery>> watching_;
};

} // namespace

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    std::string address;
    try {
        address = argc == 3 && std::string(argv[1]) == "--socket"
                      ? argv[2]
                      : yi::managed([](const char *name) { return std::getenv(name); });
    } catch (const std::exception &e) {
        std::cerr << "panel: " << e.what() << "\n";
        return 2;
    }
    std::unique_ptr<yi::Attachment> attachment;
    try {
        attachment = yi::Attachment::attach(address);
    } catch (const std::exception &e) {
        std::cerr << "panel: the channel at " << address << " refused the attachment: " << panel::said(e) << "\n";
        return 1;
    }
    std::cout << "panel: attached to " << address << " at the contract's version " << attachment->version()
              << std::endl;
    if (const char *label = std::getenv("STATION_LABEL")) {
        app.setApplicationDisplayName(label);
    }

    Attached acts(*attachment);
    panel::Window window(acts);
    std::mutex mu;
    panel::Picture picture(attachment->picture());
    auto draw = [&window](panel::Picture copy) {
        QMetaObject::invokeMethod(&window, [&window, copy] {
            window.draw(copy);
            std::cout << panel::summary(copy) << std::flush;
        });
    };
    draw(picture);
    window.show();

    // The standing subscription, followed away from the window: each subject it names read again, and
    // the sequence the picture is current to confirmed once applied.
    std::thread following([&] {
        yi::Subscription *standing = attachment->standing();
        std::uint64_t confirmed = picture.applied();
        auto read = [&](const std::string &kind, const std::string &identity) { return attachment->read(kind, identity); };
        try {
            while (standing) {
                auto d = standing->next();
                if (!d) {
                    break;
                }
                std::unique_lock<std::mutex> hold(mu);
                if (picture.apply(*d, read)) {
                    draw(picture);
                }
                std::uint64_t applied = picture.applied();
                hold.unlock();
                if (applied != confirmed) {
                    attachment->confirm(standing->id(), applied);
                    confirmed = applied;
                }
            }
        } catch (const std::exception &e) {
            std::cerr << "panel: " << panel::said(e) << "\n";
        }
        // The attachment ended: the panel has nothing left to show.
        QMetaObject::invokeMethod(&app, [] { QApplication::quit(); });
    });
    int status = app.exec();
    attachment->close();
    following.join();
    return status;
}
